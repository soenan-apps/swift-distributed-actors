// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
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
import XCTest

@testable import DistributedCluster

// Unit tests of the actions, see `ClusterLeaderActionsClusteredTests` for integration tests
internal final class ClusterLeaderActionsTests: XCTestCase {
    private let _endpointA: Cluster.Endpoint = Cluster.Endpoint(systemName: "nodeA", host: "1.1.1.1", port: 7_337)
    private let _endpointB: Cluster.Endpoint = Cluster.Endpoint(systemName: "nodeB", host: "2.2.2.2", port: 8_228)
    private let _endpointC: Cluster.Endpoint = Cluster.Endpoint(systemName: "nodeC", host: "3.3.3.3", port: 9_119)

    private var allNodes: [Cluster.Node] {
        [self.nodeA, self.nodeB, self.nodeC]
    }

    private lazy var stateA: ClusterShellState = ClusterShellState.makeTestMock(side: .server) { settings in
        settings.endpoint = self._endpointA
    }
    private lazy var stateB: ClusterShellState = ClusterShellState.makeTestMock(side: .server) { settings in
        settings.endpoint = self._endpointB
    }
    private lazy var stateC: ClusterShellState = ClusterShellState.makeTestMock(side: .server) { settings in
        settings.endpoint = self._endpointC
    }

    private var nodeA: Cluster.Node {
        self.stateA.selfNode
    }

    private var nodeB: Cluster.Node {
        self.stateB.selfNode
    }

    private var nodeC: Cluster.Node {
        self.stateC.selfNode
    }

    override internal func setUp() {
        self.stateA = ClusterShellState.makeTestMock(side: .server) { settings in
            settings.endpoint = self._endpointA
        }
        self.stateB = ClusterShellState.makeTestMock(side: .server) { settings in
            settings.endpoint = self._endpointB
        }
        self.stateC = ClusterShellState.makeTestMock(side: .server) { settings in
            settings.endpoint = self._endpointC
        }

        _ = self.stateA.membership.join(self.nodeA)
        _ = self.stateA.membership.join(self.nodeB)
        _ = self.stateA.membership.join(self.nodeC)

        _ = self.stateB.membership.join(self.nodeA)
        _ = self.stateB.membership.join(self.nodeB)
        _ = self.stateB.membership.join(self.nodeC)

        _ = self.stateC.membership.join(self.nodeA)
        _ = self.stateC.membership.join(self.nodeB)
        _ = self.stateC.membership.join(self.nodeC)
        _ = self.stateA.latestGossip.mergeForward(incoming: self.stateB.latestGossip)

        _ = self.stateA.latestGossip.mergeForward(incoming: self.stateC.latestGossip)

        _ = self.stateB.latestGossip.mergeForward(incoming: self.stateA.latestGossip)
        _ = self.stateC.latestGossip.mergeForward(incoming: self.stateA.latestGossip)
    }

    override internal func tearDown() {
        self.stateA.latestGossipStorage.membership = .empty
        self.stateA.latestGossipStorage.seen.underlying.removeAll()
        self.stateB.latestGossipStorage.membership = .empty
        self.stateB.latestGossipStorage.seen.underlying.removeAll()
        self.stateC.latestGossipStorage.membership = .empty
        self.stateC.latestGossipStorage.seen.underlying.removeAll()
        super.tearDown()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Moving members to .removed

    internal func test_leaderActions_removeDownMembers_ifKnownAsDownToAllMembers() throws {
        // make A the leader
        let leader: Cluster.Member = try XCTUnwrap(
            self.stateA.membership.anyMember(forEndpoint: self.nodeA.endpoint)
        )
        let makeFirstTheLeader: Cluster.LeadershipChange = try XCTUnwrap(
            Cluster.LeadershipChange(oldLeader: nil, newLeader: leader)
        )
        _ = self.stateA.applyClusterEvent(.leadershipChange(makeFirstTheLeader))

        // time to mark B as .down
        _ = self.stateA.membership.mark(self.nodeB, as: .down)  // only F knows that S is .down

        // ensure some nodes are up, so they participate in the convergence check
        _ = self.stateA.membership.mark(self.nodeA, as: .operational)
        _ = self.stateA.membership.mark(self.nodeC, as: .operational)

        // not yet converged, the first/third members need to chat some more, to ensure first knows that third knows
        // that second is down
        self.stateA.latestGossip.converged().shouldBeFalse()
        let moveMembersUp: [ClusterShellState.LeaderAction] = self.stateA.collectLeaderActions()
        moveMembersUp.count.shouldEqual(0)

        // we tell others about the latest gossip, that B is down
        // second does not get the information, let's assume we cannot communicate with it
        self.gossip(from: self.stateA, to: &self.stateC)

        // first and second now know that second is down
        try XCTUnwrap(self.stateA.membership.member(self.nodeB)).status.shouldEqual(.down)
        try XCTUnwrap(self.stateC.membership.member(self.nodeB)).status.shouldEqual(.down)

        // we gossiped to C, and it knows, but we don't know yet if it knows (if it has received the information)
        self.stateA.latestGossip.converged().shouldBeFalse()

        // after a gossip back...
        self.gossip(from: self.stateC, to: &self.stateA)

        // now first knows that all other up/leaving members also know about second being .down
        self.stateA.latestGossip.converged().shouldBeTrue()
        // also true, but not needed for the leader to make the decision
        self.stateC.latestGossip.converged().shouldBeTrue()

        let hopefullyRemovalActions: [ClusterShellState.LeaderAction] = self.stateA.collectLeaderActions()
        hopefullyRemovalActions.count.shouldEqual(1)
        guard case .some(.removeMember(let member)) = hopefullyRemovalActions.first else {
            XCTFail("Expected a member removal action, but did not get one, actions: \(hopefullyRemovalActions)")
            return
        }
        member.status.isDown.shouldBeTrue()
        member.node.shouldEqual(self.nodeB)

        // interpret leader actions would interpret it by removing the member now and tombstone-ing it,
        // see `interpretLeaderActions`
        _ = self.stateA.membership.removeCompletely(self.nodeB)
        self.stateA.latestGossip.membership.member(self.nodeB).shouldBeNil()

        // once we (leader) have performed removal and talk to others, they should also remove and prune seen tables
        //
        // once a node is removed, it should not be seen in gossip seen tables anymore
        _ = self.gossip(from: self.stateA, to: &self.stateC)
    }

    internal func test_leaderActions_removeDownMembers_dontRemoveIfDownNotKnownToAllMembersYet() throws {
        // A is .down, but
        self.stateB.latestGossipStorage = try .parse(
            """
            A.down B.up C.up [leader:B]
            A: A:7 B:2
            B: A:7 B:10 C:6
            C: A:7 B:5 C:6
            """,
            owner: self.nodeB,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        self.stateB.latestGossip.converged().shouldBeFalse()
        let moveMembersUp: [ClusterShellState.LeaderAction] = self.stateA.collectLeaderActions()
        moveMembersUp.count.shouldEqual(0)
    }

    @discardableResult
    private func gossip(
        from source: ClusterShellState,
        to target: inout ClusterShellState
    ) -> Cluster.MembershipGossip.MergeDirective {
        target.latestGossip.mergeForward(incoming: source.latestGossip)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Moving members .up

    // TODO: same style of tests for upNumbers and moving members up
}
