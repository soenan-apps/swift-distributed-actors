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
import SWIM
import XCTest

@testable import DistributedCluster

// "Get down!"
internal final class DowningClusteredTests: ClusteredActorSystemsXCTestCase {
    internal enum NodeStopMethod {
        case downFromOtherMember
        case downSelf
        case leaveSelfNode
        case shutdownSelf
    }

    /// Selects which node to stop
    internal enum StopNodeSelection {
        // the first node is going to be the leader,
        // so testing for downing the leader and a non-leader is recommended.
        case firstLeader
        case secondNonLeader
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Shared Settings

    internal var downingStrategy: DowningStrategySettings {
        .timeout(.init(downUnreachableMembersAfter: .milliseconds(200)))
    }

    override internal func configureLogCapture(settings: inout LogCapture.Settings) {
        settings.excludeActorPaths = [
            "/system/replicator",
            "/system/replicator/gossip",
            "/system/receptionist",
            "/system/cluster/swim",
        ]
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Downing

    internal func shared_stoppingNode_shouldPropagateToOtherNodesAsDown(
        stopMethod: NodeStopMethod,
        stopNode: StopNodeSelection,
        _ modifySettings: ((inout ClusterSystemSettings) -> Void)?
    ) async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await self.setUpPair { settings in
            settings.swim.probeInterval = .milliseconds(500)
            modifySettings?(&settings)
        }

        let thirdNeverDownSystem: ClusterSystem = await self.setUpNode("third", modifySettings)

        try await self.joinNodes(node: first, with: second, ensureMembers: .operational)
        try await self.joinNodes(node: thirdNeverDownSystem, with: second, ensureMembers: .operational)

        let (expectedDownSystem, otherNotDownPairSystem): (ClusterSystem, ClusterSystem) =
            self.stoppedNodes(for: stopNode, first: first, second: second)

        let expectedDownNode: Cluster.Node = expectedDownSystem.cluster.node

        // we start cluster event probes early, so they get the events one by one as they happen
        let eventsProbeOther: ActorTestProbe<Cluster.Event> =
            await self.testKit(otherNotDownPairSystem).spawnClusterEventStreamTestProbe()
        let eventsProbeThird: ActorTestProbe<Cluster.Event> =
            await self.testKit(thirdNeverDownSystem).spawnClusterEventStreamTestProbe()

        // we cause the stop of the target node as expected
        try self.stopNode(
            using: stopMethod,
            selected: stopNode,
            first: first,
            second: second,
            observer: thirdNeverDownSystem
        )

        // collect all events regarding the expectedDownNode's membership lifecycle
        // - the timeout is fairly large here to tolerate slow CI and variations how the events get propagated,
        // normally they propagate quite quickly
        // - we only check for "did it become down (or was it removed even already), because that's the purpose of
        // these tests
        //   - we have more specific tests which ensure that a down is issued followed by a removal (and here it
        // happens usually as well,
        //     but in order to de-sensitivize the test to timing, we only check for what we actually care about
        // note also that technically we may only "so far" only get a down, and that's okay, the removal would
        // follow soon
        let eventsOnOther: [Cluster.MembershipChange] =
            try eventsProbeOther.fishFor(
                Cluster.MembershipChange.self,
                within: .seconds(30),
                expectedDownMemberEventsFishing(
                    expectedDownSystem: expectedDownSystem,
                    expectedDownNode: expectedDownNode,
                    stopMethod: stopMethod,
                    on: otherNotDownPairSystem
                )
            )
        eventsOnOther.shouldContain { change in change.status.isAtLeast(.down) }

        let eventsOnThird: [Cluster.MembershipChange] =
            try eventsProbeThird.fishFor(
                Cluster.MembershipChange.self,
                within: .seconds(30),
                expectedDownMemberEventsFishing(
                    expectedDownSystem: expectedDownSystem,
                    expectedDownNode: expectedDownNode,
                    stopMethod: stopMethod,
                    on: thirdNeverDownSystem
                )
            )
        eventsOnThird.shouldContain { change in change.status.isAtLeast(.down) }
    }

    private func stoppedNodes(
        for selection: StopNodeSelection, first: ClusterSystem, second: ClusterSystem
    ) -> (ClusterSystem, ClusterSystem) {
        switch selection {
        case .firstLeader:
            return (first, second)

        case .secondNonLeader:
            return (second, first)
        }
    }

    private func stopNode(
        using method: NodeStopMethod,
        selected: StopNodeSelection,
        first: ClusterSystem,
        second: ClusterSystem,
        observer: ClusterSystem
    ) throws {
        switch (method, selected) {
        case (.leaveSelfNode, .firstLeader):
            first.cluster.leave()

        case (.leaveSelfNode, .secondNonLeader):
            second.cluster.leave()

        case (.downSelf, .firstLeader):
            first.cluster.down(
                endpoint:
                    first.cluster.node.endpoint
            )

        case (.downSelf, .secondNonLeader):
            second.cluster.down(
                endpoint:
                    second.cluster.node.endpoint
            )

        case (.shutdownSelf, .firstLeader):
            try first.shutdown()

        case (.shutdownSelf, .secondNonLeader):
            try second.shutdown()

        case (.downFromOtherMember, .firstLeader):
            second.cluster.down(
                endpoint:
                    first.cluster.node.endpoint
            )

        case (.downFromOtherMember, .secondNonLeader):
            observer.cluster.down(
                endpoint:
                    second.cluster.node.endpoint
            )
        }
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: "Mass" Downing

    internal func test_many_nonLeaders_shouldPropagateToOtherNodes() async throws {
        if Int.random(in: 10...100) > 0 {
            throw XCTSkip(
                "SKIPPING FLAKY TEST, REVISIT IT SOON"
            )  // FIXME: https://github.com/apple/swift-distributed-actors/issues/712
        }

        var nodes: [ClusterSystem] = []
        for index in (1...7) {
            nodes[index] = await setUpNode("node-\(index)")
        }

        let first: ClusterSystem = try XCTUnwrap(nodes.first)

        var probes: [Cluster.Node: ActorTestProbe<Cluster.Event>] = [:]
        for remainingNode in nodes {
            probes[remainingNode.cluster.node] = await self.testKit(remainingNode).spawnClusterEventStreamTestProbe()
        }

        pinfo("Joining \(nodes.count) nodes...", file: #fileID, line: #line)
        let joiningStart: ContinuousClock.Instant = ContinuousClock.Instant.now

        for node in nodes { first.cluster.join(endpoint: node.cluster.node.endpoint) }
        try await self.ensureNodes(.operational, nodes: nodes.map(\.cluster.node), within: .seconds(30))

        let joiningStop: ContinuousClock.Instant = ContinuousClock.Instant.now
        pinfo(
            "Joined \(nodes.count) nodes, took: \((joiningStop - joiningStart).prettyDescription)",
            file: #fileID,
            line: #line
        )

        let nodesToDown: ArraySlice<ClusterSystem> = nodes.prefix(nodes.count / 2)
        var remainingNodes: [ClusterSystem] = nodes
        remainingNodes.removeFirst(nodesToDown.count)

        pinfo("Downing \(nodesToDown.count) nodes: \(nodesToDown.map(\.cluster.node))", file: #fileID, line: #line)
        for node in nodesToDown {
            try await node.shutdown().wait()
        }

        for remainingNode in remainingNodes {
            let probe: ActorTestProbe<Cluster.Event> = try XCTUnwrap(probes[remainingNode.cluster.node])
            let events: [Cluster.MembershipChange] =
                try probe.fishFor(
                    Cluster.MembershipChange.self,
                    within: .seconds(60),
                    expectedDownMemberEventsFishing(for: nodesToDown, on: remainingNode)
                )

            self.assertDownAndRemovalEvents(events, for: nodesToDown)
        }
    }

    private func assertDownAndRemovalEvents(
        _ events: [Cluster.MembershipChange],
        for nodesToDown: ArraySlice<ClusterSystem>
    ) {
        events.shouldContain { change in
            change.status.isDown
                && (change.previousStatus == .joining || change.previousStatus == .operational)
        }
        for expectedDownNode in nodesToDown {
            events.shouldContain(
                Cluster.MembershipChange(
                    node: expectedDownNode.cluster.node,
                    previousStatus: .down,
                    toStatus: .removed
                )
            )
        }
    }

    private func expectedDownMemberEventsFishing(
        for nodesToDown: ArraySlice<ClusterSystem>,
        on observedSystem: ClusterSystem,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> (Cluster.Event) -> ActorTestProbe<Cluster.Event>.FishingDirective<Cluster.MembershipChange> {
        pinfo(
            """
            Expecting \(nodesToDown.map(\.cluster.node.endpoint)) to become [.down] on \
            [\(observedSystem.cluster.node.endpoint)]
            """,
            file: #fileID,
            line: #line
        )
        var removalsFound: Int = 0

        return { event in
            switch event {
            case .membershipChange(let change) where change.isRemoval:
                pinfo("\(observedSystem.cluster.node.endpoint): \(change)", file: file, line: line)
                removalsFound += 1
                if removalsFound == nodesToDown.count {
                    return .catchComplete(change)
                }
                return .catchContinue(change)

            case .membershipChange(let change) where change.isDown:
                pinfo("\(observedSystem.cluster.node.endpoint): \(change)", file: file, line: line)
                return .catchContinue(change)

            default:
                return .ignore
            }
        }
    }

    private func expectedDownMemberEventsFishing(
        expectedDownSystem: ClusterSystem,
        expectedDownNode: Cluster.Node,
        stopMethod: NodeStopMethod,
        on observedSystem: ClusterSystem,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> (Cluster.Event) -> ActorTestProbe<Cluster.Event>.FishingDirective<Cluster.MembershipChange> {
        pinfo(
            """
            Expecting [\(expectedDownSystem)] to become [.down] on [\(observedSystem.cluster.node.endpoint)], method \
            to stop the node [\(stopMethod)]
            """,
            file: #fileID,
            line: #line
        )

        return { event in
            switch event {
            case .membershipChange(let change) where change.node == expectedDownNode && change.isRemoval:
                pinfo("\(observedSystem.cluster.node.endpoint): \(change)", file: (file), line: line)
                return .catchComplete(change)

            case .membershipChange(let change) where change.node == expectedDownNode:
                pinfo("\(observedSystem.cluster.node.endpoint): \(change)", file: (file), line: line)
                return .catchContinue(change)

            case .reachabilityChange(let change) where change.member.node == expectedDownNode:
                pnote("\(observedSystem.cluster.node.endpoint): \(change)", file: (file), line: line)
                return .ignore

            default:
                pnote("\(observedSystem.cluster.node.endpoint): \(event)", file: (file), line: line)
                return .ignore
            }
        }
    }
}
