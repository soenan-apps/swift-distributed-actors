// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import Logging
import XCTest

@testable import DistributedCluster

internal final class ClusterSingletonPluginClusteredTests: ClusteredActorSystemsXCTestCase {
    override internal func configureLogCapture(settings: inout LogCapture.Settings) {
        settings.excludeActorPaths = [
            "/system/swim",
            "/system/cluster/swim",
            "/system/cluster",
            "/system/cluster/gossip",
            "/system/receptionist",
        ]
    }

    internal func test_singletonByClusterLeadership_happyPath() async throws {
        var settings: ClusterSingletonSettings = ClusterSingletonSettings()
        settings.allocationStrategy = .byLeadership

        let first: ClusterSystem = await makeSingletonNode("first", port: 7_111, minimumMembers: 3)
        let second: ClusterSystem = await makeSingletonNode("second", port: 8_222, minimumMembers: 3)
        let third: ClusterSystem = await makeSingletonNode("third", port: 9_333, minimumMembers: 3)

        // Start the singleton boss before forming the cluster (upstream issue #463).
        let name: String = "the-one"
        let ref1: TheSingleton = try await hostSingleton(on: first, name: name, settings: settings, greeting: "Hello-1")
        let ref2: TheSingleton = try await hostSingleton(
            on: second,
            name: name,
            settings: settings,
            greeting: "Hello-2"
        )
        let ref3: TheSingleton = try await hostSingleton(on: third, name: name, settings: settings, greeting: "Hello-3")

        first.cluster.join(endpoint: second.cluster.node.endpoint)
        third.cluster.join(endpoint: first.cluster.node.endpoint)

        // `first` will be the leader (lowest address) and runs the singleton
        try await self.ensureNodes(
            .operational,
            nodes: second.cluster.node,
            third.cluster.node,
            on: first,
            within: .seconds(10)
        )

        try await assertInitialSingletonReplies(
            first: (system: first, singleton: ref1),
            second: (system: second, singleton: ref2),
            third: (system: third, singleton: ref3)
        )
    }

    internal func test_singleton_lifecycle() async throws {
        var settings: ClusterSingletonSettings = ClusterSingletonSettings()
        settings.allocationStrategy = .byLeadership

        let first: ClusterSystem = await makeSingletonNode("first", port: 7_111, minimumMembers: 1)

        let probe: ActorTestProbe<String> = self.testKit(first).makeTestProbe("p1", expecting: String.self)

        let name: String = "the-one"
        _ = try await first.singleton.host(name: name, settings: settings) { actorSystem in
            LifecycleTestSingleton(probe: probe, actorSystem: actorSystem)
        }

        // `first` will be the leader (lowest address) and runs the singleton
        try await first.cluster.joined(within: .seconds(20))

        try probe.expectMessage(prefix: "init")
        try probe.expectMessage(prefix: "activate")

        // pretend we're handing over to somewhere else:
        let optionalBoss: ClusterSingletonBoss<LifecycleTestSingleton>? = await first.singleton.singletonBoss(
            name: name,
            type: LifecycleTestSingleton.self
        )
        let boss: ClusterSingletonBoss<LifecycleTestSingleton> = try XCTUnwrap(optionalBoss)
        await boss.whenLocal { localBoss in localBoss.handOver(to: nil) }

        try probe.expectMessage(prefix: "passivate")
        try probe.expectMessage(prefix: "deinit")
    }

    internal func test_singletonByClusterLeadership_stashMessagesIfNoLeader() async throws {
        var settings: ClusterSingletonSettings = ClusterSingletonSettings()
        settings.allocationStrategy = .byLeadership
        settings.allocationTimeout = .seconds(15)

        let first: ClusterSystem = await makeSingletonNode("first", port: 7_111, minimumMembers: 3)
        let second: ClusterSystem = await makeSingletonNode("second", port: 8_222, minimumMembers: 3)
        let third: ClusterSystem = await makeSingletonNode("third", port: 9_333, minimumMembers: 3)

        // Bring up `ClusterSingletonBoss`. No leader yet so singleton is not available.
        let name: String = "the-one"
        let ref1: TheSingleton = try await hostSingleton(on: first, name: name, settings: settings, greeting: "Hello-1")
        let ref2: TheSingleton = try await hostSingleton(
            on: second,
            name: name,
            settings: settings,
            greeting: "Hello-2"
        )
        let ref3: TheSingleton = try await hostSingleton(on: third, name: name, settings: settings, greeting: "Hello-3")

        try await withThrowingTaskGroup(of: SingletonStashTaskResult.self) { group in
            group.addTask {
                // Set up the cluster
                first.cluster.join(endpoint: second.cluster.node.endpoint)
                third.cluster.join(endpoint: first.cluster.node.endpoint)

                // `first` will be the leader (lowest address) and runs the singleton.
                //
                // Leader selection requires all three nodes; an explicit status wait can finish after replies.
                // and it's possible for `ensureNodes` to return positive response *after* singleton has been allocated,
                // which means stashed calls have started getting processed and that would cause the test to fail.

                return SingletonStashTaskResult.cluster
            }

            // Remote calls should be stashed until singleton is allocated
            group.addTask(
                operation: stashedGreeting(
                    singleton: ref1,
                    greetingName: "Alice",
                    expectedPrefix: "Hello-1 Alice!"
                )
            )
            group.addTask(
                operation: stashedGreeting(
                    singleton: ref2,
                    greetingName: "Bob",
                    expectedPrefix: "Hello-1 Bob!"
                )
            )
            group.addTask(
                operation: stashedGreeting(
                    singleton: ref3,
                    greetingName: "Charlie",
                    expectedPrefix: "Hello-1 Charlie!"
                )
            )

            try await assertClusterTaskFinishedFirst(&group)
        }
    }

    internal func test_singletonByClusterLeadership_withLeaderChange() async throws {
        var settings: ClusterSingletonSettings = ClusterSingletonSettings()
        settings.allocationStrategy = .byLeadership
        settings.allocationTimeout = .seconds(15)

        let first: ClusterSystem = await makeSingletonNode("first", port: 7_111, minimumMembers: 3)
        let second: ClusterSystem = await makeSingletonNode("second", port: 8_222, minimumMembers: 3)
        let third: ClusterSystem = await makeSingletonNode("third", port: 9_333, minimumMembers: 3)
        let fourth: ClusterSystem = await makeSingletonNode("fourth", port: 7_444, minimumMembers: 3)

        // Bring up `ClusterSingletonBoss`
        let name: String = "the-one"
        let ref1: TheSingleton = try await hostSingleton(on: first, name: name, settings: settings, greeting: "Hello-1")
        let ref2: TheSingleton = try await hostSingleton(
            on: second,
            name: name,
            settings: settings,
            greeting: "Hello-2"
        )
        let ref3: TheSingleton = try await hostSingleton(on: third, name: name, settings: settings, greeting: "Hello-3")
        _ = try await hostSingleton(on: fourth, name: name, settings: settings, greeting: "Hello-4")

        first.cluster.join(endpoint: second.cluster.node.endpoint)
        third.cluster.join(endpoint: first.cluster.node.endpoint)

        // `first` will be the leader (lowest address) and runs the singleton
        try await self.ensureNodes(
            .operational,
            nodes: second.cluster.node,
            third.cluster.node,
            on: first,
            within: .seconds(10)
        )
        pinfo("Nodes up: \([first.cluster.node, second.cluster.node, third.cluster.node])", file: #fileID, line: #line)

        try await assertInitialSingletonReplies(
            first: (system: first, singleton: ref1),
            second: (system: second, singleton: ref2),
            third: (system: third, singleton: ref3)
        )
        pinfo("All three nodes communicated with singleton", file: #fileID, line: #line)

        try await assertSingletonLeadershipHandover(
            first: first,
            second: (system: second, singleton: ref2),
            third: (system: third, singleton: ref3),
            fourth: fourth
        )
    }

    // https://github.com/apple/swift-distributed-actors/issues/1195
    internal func disabledTestRemoteCallShouldFailAfterAllocationTimedOut() async throws {
        var settings: ClusterSingletonSettings = ClusterSingletonSettings()
        settings.allocationStrategy = .byLeadership
        settings.allocationTimeout = .milliseconds(100)

        let first: ClusterSystem = await makeSingletonNode("first", port: 7_111, minimumMembers: 2)
        let second: ClusterSystem = await makeSingletonNode("second", port: 8_222, minimumMembers: 2)

        // Start the singleton boss before forming the cluster (upstream issue #463).
        let name: String = "the-one"
        _ = try await hostSingleton(on: first, name: name, settings: settings, greeting: "Hello-1")
        let ref2: TheSingleton = try await hostSingleton(
            on: second,
            name: name,
            settings: settings,
            greeting: "Hello-2"
        )

        first.cluster.join(endpoint: second.cluster.node.endpoint)

        // `first` will be the leader (lowest address) and runs the singleton
        try await self.ensureNodes(.operational, nodes: second.cluster.node, on: first)

        try await self.assertSingletonRequestReply(
            second,
            singleton: ref2,
            greetingName: "Bob",
            expectedPrefix: "Hello-1 Bob!"
        )

        let firstNode: Cluster.Node = first.cluster.node
        first.cluster.leave()

        try await self.assertMemberStatus(on: second, node: firstNode, is: .down, within: .seconds(10))

        // Make sure that `second` and `third` see `first` as down and become leader-less
        try self.testKit(second).eventually(within: .seconds(10)) {
            try self.assertLeaderNode(on: second, is: nil)
        }

        // This should take us over allocation timeout. Singleton is nil since there is no leader.
        try await Task.sleep(nanoseconds: 500_000_000)

        let error: any Error = try await shouldThrow {
            _ = try await ref2.greet(name: "Bob")
        }
        guard case ClusterSingletonError.allocationTimeout = error else {
            throw self.testKit(second).fail("Expected ClusterSingletonError.allocationTimeout, got \(error)")
        }
    }

}
