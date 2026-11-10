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
    internal func test_mergeForward_incomingGossip_firstGossipFromOtherNode() throws {
        var gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.joining
            A: A:1
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let incoming: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            B.joining
            B: B:1
            """,
            owner: self.nodeB,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let directive: Cluster.MembershipGossip.MergeDirective = gossip.mergeForward(incoming: incoming)

        directive.effectiveChanges.shouldEqual(
            [Cluster.MembershipChange(node: self.nodeB, previousStatus: nil, toStatus: .joining)]
        )

        gossip.shouldEqual(
            try Cluster.MembershipGossip.parse(
                """
                A.joining B.joining
                A: A:1 B:1
                B: B:1
                """,
                owner: self.nodeA,
                nodes: self.allNodes,
                file: #file,
                line: #line
            )
        )
    }

    internal func test_mergeForward_incomingGossip_firstGossipFromOtherNodes() throws {
        var gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.joining
            A: A:1
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let incoming: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            B.joining C.joining
            B: B:1 C:1
            C: B:1 C:1
            """,
            owner: self.nodeB,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let directive: Cluster.MembershipGossip.MergeDirective = gossip.mergeForward(incoming: incoming)

        Set(directive.effectiveChanges).shouldEqual(
            Set(
                [
                    Cluster.MembershipChange(node: self.nodeB, previousStatus: nil, toStatus: .joining),
                    Cluster.MembershipChange(node: self.nodeC, previousStatus: nil, toStatus: .joining),
                ]
            )
        )

        let expected: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.joining B.joining C.joining
            A: A:1 B:1 C:1
            B: B:1 C:1
            C: B:1 C:1
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        gossip.seen.shouldEqual(expected.seen)
        gossip.seen.version(at: self.nodeA).shouldEqual(expected.seen.version(at: self.nodeA))
        gossip.seen.version(at: self.nodeB).shouldEqual(expected.seen.version(at: self.nodeB))
        gossip.seen.version(at: self.nodeC).shouldEqual(expected.seen.version(at: self.nodeC))
        gossip.membership.shouldEqual(expected.membership)
        gossip.shouldEqual(expected)
    }

    internal func test_mergeForward_incomingGossip_sameVersions() {
        var gossip: Cluster.MembershipGossip = Cluster.MembershipGossip(ownerNode: self.nodeA)
        _ = gossip.membership.join(self.nodeA)
        gossip.seen.incrementVersion(owner: self.nodeB, at: self.nodeA)  // v: myself:1, second:1
        _ = gossip.membership.join(self.nodeB)  // myself:joining, second:joining

        let gossipFromSecond: Cluster.MembershipGossip = Cluster.MembershipGossip(ownerNode: self.nodeB)
        let directive: Cluster.MembershipGossip.MergeDirective = gossip.mergeForward(incoming: gossipFromSecond)

        directive.effectiveChanges.shouldEqual([])
    }

    internal func test_mergeForward_incomingGossip_fromFourth_onlyKnowsAboutItself() throws {
        var gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.joining B.joining B.joining
            A: A@1 B@1 C@1
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        // only knows about fourth, while myGossip has first, second and third
        let incomingGossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            D.joining
            D: D@1
            """,
            owner: self.fourthNode,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let directive: Cluster.MembershipGossip.MergeDirective = gossip.mergeForward(incoming: incomingGossip)

        // this test also covers so <none> does not accidentally cause changes into .removed, which would be
        // catastrophic
        directive.causalRelation.shouldEqual(.concurrent)
        directive.effectiveChanges.shouldEqual(
            [Cluster.MembershipChange(node: self.fourthNode, previousStatus: nil, toStatus: .joining)]
        )
        gossip.shouldEqual(
            try Cluster.MembershipGossip.parse(
                """
                A.joining B.joining C.joining
                A: A@1 B@1 C@1 D@1
                D: D@1
                """,
                owner: self.nodeA,
                nodes: self.allNodes,
                file: #file,
                line: #line
            )
        )
    }
}
