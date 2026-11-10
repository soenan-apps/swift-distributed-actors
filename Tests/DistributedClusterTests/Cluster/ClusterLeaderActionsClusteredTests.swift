// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import Foundation
import NIOSSL
import SWIM
import XCTest

@testable import DistributedCluster

internal final class ClusterLeaderActionsClusteredTests: ClusteredActorSystemsXCTestCase {
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: leader decision: .joining -> .up

    internal func test_singleLeader() async throws {
        let first: ClusterSystem = await setUpNode("first") { settings in
            settings.endpoint.port = 7_111
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 1)
        }

        let probe: ActorTestProbe<Cluster.Event> = self.testKit(first).makeTestProbe(expecting: Cluster.Event.self)

        _ = try first.spawn(
            "selfishSingleLeader",
            Behavior<Cluster.Event>.setup { context in
                context.system.cluster.events.subscribe(context.myself)

                return .receiveMessage { event in
                    switch event {
                    case .leadershipChange:
                        probe.tell(event)
                        return .same

                    default:
                        return .same
                    }
                }
            }
        )

        switch try probe.expectMessage() {
        case .leadershipChange(let change):
            guard let leader = change.newLeader else {
                throw self.testKit(first).fail("Expected \(first.cluster.node) to be leader")
            }
            leader.node.shouldEqual(first.cluster.node)

        default:
            throw self.testKit(first).fail("Expected leader change event")
        }
    }

    internal func test_joining_to_up_decisionByLeader() async throws {
        let first: ClusterSystem = await setUpNode("first") { settings in
            settings.endpoint.port = 7_111
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 3)
        }

        let second: ClusterSystem = await setUpNode("second") { settings in
            settings.endpoint.port = 8_222
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 3)
        }

        let third: ClusterSystem = await setUpNode("third") { settings in
            settings.endpoint.port = 9_333
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 3)
        }

        first.cluster.join(endpoint: second.cluster.node.endpoint)
        third.cluster.join(endpoint: second.cluster.node.endpoint)

        try assertAssociated(first, withAtLeast: second.cluster.node)
        try assertAssociated(second, withAtLeast: third.cluster.node)
        try assertAssociated(first, withAtLeast: third.cluster.node)

        try await self.assertMemberStatus(on: first, node: first.cluster.node, is: .operational, within: .seconds(10))
        try await self.assertMemberStatus(on: first, node: second.cluster.node, is: .operational, within: .seconds(10))
        try await self.assertMemberStatus(on: first, node: third.cluster.node, is: .operational, within: .seconds(10))

        try await self.assertMemberStatus(on: second, node: first.cluster.node, is: .operational, within: .seconds(10))
        try await self.assertMemberStatus(on: second, node: second.cluster.node, is: .operational, within: .seconds(10))
        try await self.assertMemberStatus(on: second, node: third.cluster.node, is: .operational, within: .seconds(10))

        try await self.assertMemberStatus(on: third, node: first.cluster.node, is: .operational, within: .seconds(10))
        try await self.assertMemberStatus(on: third, node: second.cluster.node, is: .operational, within: .seconds(10))
        try await self.assertMemberStatus(on: third, node: third.cluster.node, is: .operational, within: .seconds(10))
    }

    internal func test_joining_to_up_earlyYetStillLettingAllNodesKnowAboutLatestMembershipStatus() async throws {
        // This showcases a racy situation, where we allow a leader elected when at least 2 nodes joined
        // yet we actually join 3 nodes -- meaning that the joining up is _slightly_ racy:
        // - maybe nodes 1 and 2 join each other first and 1 starts upping
        // - maybe nodes 2 and 3 join each other and 2 starts upping
        // - and at the same time, maybe while 1 and 2 have started joining, 2 and 3 already joined, and 2 issued up
        // for itself and 3
        //
        // All this is _fine_. The cluster leader is such that under whichever rules we allowed it to be elected
        // it shall perform its duties. This tests however quickly shows that lack of letting the "third" node,
        // via gossip or some other way about the ->up of other nodes once it joins the "others", it'd be stuck
        // waiting for
        // the ->up forever.
        //
        // In other words, this test exercises that there must be _some_ (gossip, or similar "push" membership once
        // a new member joins),
        // to a new member.
        //
        let first: ClusterSystem = await setUpNode("first") { settings in
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)
        }

        let second: ClusterSystem = await setUpNode("second") { settings in
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)
        }

        let third: ClusterSystem = await setUpNode("third") { settings in
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)
        }

        let fourth: ClusterSystem = await setUpNode("fourth") { settings in
            // even without election running, it will be notified by things by the others
            settings.autoLeaderElection = .disabled
        }

        first.cluster.join(endpoint: second.cluster.node.endpoint)
        third.cluster.join(endpoint: second.cluster.node.endpoint)
        try await self.ensureNodes(
            .operational,
            nodes: first.cluster.node,
            second.cluster.node,
            third.cluster.node,
            within: .seconds(10)
        )

        // Even the fourth node now could join and be notified about all the existing up members.
        // It does not even have to run any leadership election -- there are leaders in the cluster.
        //
        // We only join one arbitrary node, we will be notified about all nodes:
        fourth.cluster.join(endpoint: third.cluster.node.endpoint)

        try await self.ensureNodes(
            .operational,
            nodes: first.cluster.node,
            second.cluster.node,
            third.cluster.node,
            fourth.cluster.node,
            within: .seconds(10)
        )
    }

}

extension ClusterLeaderActionsClusteredTests {
    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: .down -> removal

    internal func test_down_to_removed_ensureRemovalHappensWhenAllHaveSeenDown() async throws {
        let first: ClusterSystem = await self.setUpRemovalNode("first")
        let firstProbe: ActorTestProbe<Cluster.Event> =
            self.testKit(first).makeTestProbe(expecting: Cluster.Event.self)
        await first.cluster.events.subscribeAndWait(firstProbe.ref)
        let second: ClusterSystem = await self.setUpRemovalNode("second")
        let third: ClusterSystem = await self.setUpRemovalNode("third")

        try await self.joinNodes(node: first, with: second)
        try await self.joinNodes(node: second, with: third)
        try await self.joinNodes(node: first, with: third)

        let secondNode: Cluster.Node = second.cluster.node
        try await self.ensureNodes(.operational, nodes: first.cluster.node, secondNode, third.cluster.node)

        first.cluster.down(endpoint: secondNode.endpoint)

        // other nodes have observed it down
        try await self.ensureNodes(atLeast: .down, nodes: secondNode, on: first)
        try await self.ensureNodes(atLeast: .down, nodes: secondNode, on: third)

        // on the leader node, the other node noticed as up:
        let eventsOnFirstSub: [Cluster.Event] = try self.captureEventsUntilDown(from: firstProbe)

        // snapshot(nil) + first nil -> joining
        // OR
        // snapshot(first joining)
        // are both legal
        eventsOnFirstSub.shouldContain(
            .membershipChange(.init(node: secondNode, previousStatus: nil, toStatus: .joining))
        )
        eventsOnFirstSub.shouldContain(
            .membershipChange(.init(node: first.cluster.node, previousStatus: .joining, toStatus: .operational))
        )
        eventsOnFirstSub.shouldContain(
            .membershipChange(.init(node: secondNode, previousStatus: .joining, toStatus: .operational))
        )
        eventsOnFirstSub.shouldContain(
            .leadershipChange(
                try XCTUnwrap(
                    Cluster.LeadershipChange(
                        oldLeader: nil,
                        newLeader: .init(node: first.cluster.node, status: .joining)
                    )
                )
            )
        )  // !-safe, since new/old leader known to be different
        eventsOnFirstSub.shouldContain(
            .membershipChange(.init(node: third.cluster.node, previousStatus: nil, toStatus: .joining))
        )
        eventsOnFirstSub.shouldContain(
            .membershipChange(.init(node: third.cluster.node, previousStatus: .joining, toStatus: .operational))
        )

        eventsOnFirstSub.shouldContain(
            .membershipChange(.init(node: secondNode, previousStatus: .operational, toStatus: .down))
        )

        try self.testKit(first).eventually(within: .seconds(3)) {
            let p1s: ActorTestProbe<Cluster.Membership> =
                self.testKit(first).makeTestProbe(expecting: Cluster.Membership.self)
            first.cluster.ref.tell(.query(.currentMembership(p1s.ref)))
        }
    }

    internal func test_ensureDownAndRemovalSpreadsToAllMembers() async throws {
        let first: ClusterSystem = await setUpNode("first") { settings in
            settings.swim.probeInterval = .milliseconds(300)
            settings.swim.pingTimeout = .milliseconds(100)
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)
            settings.downingStrategy = .timeout(.init(downUnreachableMembersAfter: .milliseconds(200)))
        }

        let firstProbe: ActorTestProbe<Cluster.Event> = self.testKit(first).makeTestProbe(expecting: Cluster.Event.self)
        await first.cluster.events.subscribeAndWait(firstProbe.ref)

        let second: ClusterSystem = await setUpNode("second") { settings in
            settings.swim.probeInterval = .milliseconds(300)
            settings.swim.pingTimeout = .milliseconds(100)
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)
            settings.downingStrategy = .timeout(.init(downUnreachableMembersAfter: .milliseconds(200)))
        }

        let secondProbe: ActorTestProbe<Cluster.Event> =
            self.testKit(second).makeTestProbe(expecting: Cluster.Event.self)
        await second.cluster.events.subscribeAndWait(secondProbe.ref)

        let third: ClusterSystem = await setUpNode("third") { settings in
            settings.swim.probeInterval = .milliseconds(300)
            settings.swim.pingTimeout = .milliseconds(100)
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)
            settings.downingStrategy = .timeout(.init(downUnreachableMembersAfter: .milliseconds(200)))
        }

        let thirdProbe: ActorTestProbe<Cluster.Event> = self.testKit(third).makeTestProbe(expecting: Cluster.Event.self)
        await third.cluster.events.subscribeAndWait(thirdProbe.ref)

        try await self.joinNodes(node: first, with: second)
        try await self.joinNodes(node: second, with: third)
        try await self.joinNodes(node: first, with: third)

        try await self.ensureNodes(.operational, nodes: first.cluster.node, second.cluster.node, third.cluster.node)

        // crash the second node
        try second.shutdown()

        // other nodes have observed it down
        try await self.ensureNodes(atLeast: .down, nodes: second.cluster.node, on: first, within: .seconds(15))
        try await self.ensureNodes(atLeast: .down, nodes: second.cluster.node, on: third, within: .seconds(15))

        try self.assertDownAndRemovalSpread(
            on: first,
            for: second.cluster.node,
            events: firstProbe,
            file: #filePath,
            line: #line
        )
    }
    private func setUpRemovalNode(_ name: String) async -> ClusterSystem {
        await self.setUpNode(name) { settings in
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)
            settings.downingStrategy = .timeout(.init(downUnreachableMembersAfter: .milliseconds(300)))
        }
    }

    private func captureEventsUntilDown(
        from probe: ActorTestProbe<Cluster.Event>,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws -> [Cluster.Event] {
        var eventsOnFirstSub: [Cluster.Event] = []
        var downFound: Bool = false
        while eventsOnFirstSub.count < 12, !downFound {
            let event: Cluster.Event = try probe.expectMessage(file: file, line: line, column: column)
            pinfo("Captured event: \(event)", file: (file), line: line)
            eventsOnFirstSub.append(event)

            switch event {
            case .membershipChange(let change) where change.status.isDown:
                downFound = true

            default:
                ()
            }
        }
        return eventsOnFirstSub
    }

    private func assertDownAndRemovalSpread(
        on first: ClusterSystem,
        for secondNode: Cluster.Node,
        events firstProbe: ActorTestProbe<Cluster.Event>,
        file: StaticString,
        line: UInt
    ) throws {
        // on the leader node, the other node noticed as up:
        let testKit: ActorTestKit = self.testKit(first)
        try testKit.eventually(within: .seconds(20), file: file, line: line) {
            let event: Cluster.Event? = try firstProbe.maybeExpectMessage()
            switch event {
            case .membershipChange(
                .init(
                    node:
                        secondNode,
                    previousStatus: .operational,
                    toStatus: .down
                )
            ):
                ()

            case let other:
                throw testKit.error(
                    "Expected `second` [     up] -> [  .down], on first node, was: \(other, orElse: "nil")",
                    file: file,
                    line: line
                )
            }
        }
        try testKit.eventually(within: .seconds(20), file: file, line: line) {
            let event: Cluster.Event? = try firstProbe.maybeExpectMessage()
            switch event {
            case .membershipChange(
                .init(
                    node:
                        secondNode,
                    previousStatus: .down,
                    toStatus: .removed
                )
            ):
                ()

            case let other:
                throw testKit.error(
                    "Expected `second` [     up] -> [  .down], on first node, was: \(other, orElse: "nil")",
                    file: file,
                    line: line
                )
            }
        }
    }

}
