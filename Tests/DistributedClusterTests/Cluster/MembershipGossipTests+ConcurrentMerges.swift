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
import NIO
import XCTest

@testable import DistributedCluster

extension MembershipGossipTests {
    internal func test_mergeForward_incomingGossip_localHasRemoved_incomingHasOldViewWithDownNode() throws {
        var gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.down C.up
            A: A@5 B@5 C@6
            B: A@5 B@5 C@6
            C: A@5 B@5 C@6
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        // while we just removed it:
        gossip.converged().shouldBeTrue()  // soundness check
        let removedMember: Cluster.Member = try XCTUnwrap(gossip.membership.member(self.nodeB))
        _ = gossip.pruneMember(removedMember)
        gossip.incrementOwnerVersion()

        let incomingOldGossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.down C.up
            A: A@5 B@5  C@6
            B: A@5 B@10 C@6
            C: A@5 B@5  C@6
            """,
            owner: self.nodeB,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )
        // TODO: this will be rejected since owner is the downed node (!)
        // add another test with third sending the same info

        let gossipBeforeMerge: Cluster.MembershipGossip = gossip
        let directive: Cluster.MembershipGossip.MergeDirective = gossip.mergeForward(incoming: incomingOldGossip)

        directive.causalRelation.shouldEqual(.concurrent)
        directive.effectiveChanges.shouldEqual(
            []  // no effect
        )

        gossip.membership.members(atLeast: .joining).shouldNotContain(removedMember)
        gossip.seen.nodes.shouldNotContain(removedMember.node)

        gossip.seen.shouldEqual(gossipBeforeMerge.seen)
        gossip.membership.shouldEqual(gossipBeforeMerge.membership)
    }

    internal func test_mergeForward_incomingGossip_concurrent_leaderDisagreement() throws {
        var gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.joining [leader:A]
            A: A@5 B@5
            B: A@5 B@5
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        // this may happen after healing a cluster partition,
        // once the nodes talk to each other again, they will run leader election and resolve the double leader
        // situation
        // until that happens, the two leaders indeed remain as-is -- as the membership itself is not the right
        // place to resolve
        // who shall be leader
        let incomingGossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.joining C.up [leader:B]
            B: B@2 C@1
            C: B@5 C@9
            """,
            owner: self.nodeC,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let directive: Cluster.MembershipGossip.MergeDirective = gossip.mergeForward(incoming: incomingGossip)

        directive.causalRelation.shouldEqual(.concurrent)
        directive.effectiveChanges.shouldEqual(
            [
                // such unknown -> up may indeed happen, if we have a large cluster, which ends up partitioned into two
                // each side keeps adding new nodes, and then the partition heals. The core membership does NOT
                // prevent this,
                // what WOULD prevent this is how the leaders are selected -- e.g. dynamic quorum etc. Though even
                // quorums can be cheated
                // in dramatic situations (e.g. we add more nodes on one side than quorum, so it gets "its illegal
                // quorum"),
                // such is the case with any "dynamic" quorum however. We CAN and will provide strategies to select
                // leaders which
                // strongly militate such risk though.
                Cluster.MembershipChange(node: self.nodeC, previousStatus: nil, toStatus: .operational)
                // note that this has NO effect on the leader; we keep trusting "our" leader,
                // leader election should kick in and reconcile those two
            ]
        )

        let expected: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.joining C.up [leader:A]
            A: A:5 B:5 C:9
            B: A:5 B:5 C@1
            C:     B:5 C:9
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        gossip.seen.shouldEqual(expected.seen)
        gossip.membership.shouldEqual(expected.membership)
        gossip.shouldEqual(expected)
    }

    internal func test_mergeForward_incomingGossip_concurrent_simple() throws {
        var gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.joining
            A: A@4
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let concurrent: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.joining B.joining
            B: B@2
            """,
            owner: self.nodeB,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let directive: Cluster.MembershipGossip.MergeDirective = gossip.mergeForward(incoming: concurrent)

        gossip.owner.shouldEqual(self.nodeA)
        directive.effectiveChanges.count.shouldEqual(0)
        gossip.shouldEqual(
            try Cluster.MembershipGossip.parse(
                """
                A.up B.joining
                A: A@4 B@2
                B: B@2
                """,
                owner: self.nodeA,
                nodes: self.allNodes,
                file: #file,
                line: #line
            )
        )
    }

    internal func test_mergeForward_incomingGossip_hasNewNode() throws {
        var gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up
            A: A@5
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        var incomingGossip: Cluster.MembershipGossip = gossip
        _ = incomingGossip.membership.join(self.nodeB)
        incomingGossip.incrementOwnerVersion()

        let directive: Cluster.MembershipGossip.MergeDirective = gossip.mergeForward(incoming: incomingGossip)

        directive.causalRelation.shouldEqual(.happenedBefore)
        directive.effectiveChanges.shouldEqual(
            [Cluster.MembershipChange(node: self.nodeB, previousStatus: nil, toStatus: .joining)]
        )

        gossip.membership.members(atLeast: .joining).shouldContain(Cluster.Member(node: self.nodeB, status: .joining))
    }
}
