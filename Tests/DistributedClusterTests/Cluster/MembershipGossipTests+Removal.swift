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
    internal func test_mergeForward_removal_incomingGossip_isAhead_hasRemovedNodeKnownToBeDown() throws {
        var gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.down C.up [leader:A]
            A: A@5 B@5 C@6
            B: A@5 B@5 C@6
            C: A@5 B@5 C@6
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let incomingGossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up C.up
            A: A@5 C@6
            C: A@5 C@7
            """,
            owner: self.nodeC,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let directive: Cluster.MembershipGossip.MergeDirective = gossip.mergeForward(incoming: incomingGossip)

        directive.causalRelation.shouldEqual(.concurrent)
        // v-clock wise this indeed is concurrent, however due to down/removal involved, we can handle it

        directive.effectiveChanges.shouldEqual(
            [
                Cluster.MembershipChange(node: self.nodeB, previousStatus: .down, toStatus: .removed)
            ]
        )

        let expectedGossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up C.up [leader:A]
            A: A@5 C@7
            C: A@5 C@7
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )
        gossip.shouldEqual(expectedGossip)
    }

    internal func test_mergeForward_incomingGossip_removal_isAhead_hasMyNodeRemoved_thusWeKeepItAsRemoved() throws {
        var gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.down C.up
            A: A@5 B@5 C@6
            B: A@5 B@5 C@6
            C: A@5 B@5 C@6
            """,
            owner: self.nodeB,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        let incomingGossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up C.up
            A: A@5 C@6
            C: A@5 C@7
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
                Cluster.MembershipChange(node: self.nodeB, previousStatus: .down, toStatus: .removed)
            ]
        )

        // we MIGHT receive a removal of "our node" however we must never apply such change!
        // we know we are `.down` and that's the most "we" will ever perceive ourselves as -- i.e. removed is only
        // for "others".
        let expected: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.removed C.up
            A: A@5 B@5 C@6
            B: A@5 B@5 C@7
            C: A@5 B@5 C@7
            """,
            owner: self.nodeB,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )
        gossip.seen.version(at: self.nodeA).shouldEqual(expected.seen.version(at: self.nodeA))
        gossip.seen.version(at: self.nodeB).shouldEqual(expected.seen.version(at: self.nodeB))
        gossip.seen.version(at: self.nodeC).shouldEqual(expected.seen.version(at: self.nodeC))
        gossip.shouldEqual(expected)
    }
}
