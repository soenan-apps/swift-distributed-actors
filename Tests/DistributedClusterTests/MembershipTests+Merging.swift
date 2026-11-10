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
import XCTest

@testable import DistributedCluster

extension MembershipTests {
    internal func test_mergeForward_fromAhead_same() {
        var membership: Cluster.Membership = self.initialMembership
        let ahead: Cluster.Membership = self.initialMembership

        let changes: [Cluster.MembershipChange] = membership.mergeFrom(incoming: ahead, myself: nil)

        changes.count.shouldEqual(0)
        membership.shouldEqual(self.initialMembership)
    }

    internal func test_mergeForward_fromAhead_membership_withAdditionalMember() throws {
        var membership: Cluster.Membership = self.initialMembership
        var ahead: Cluster.Membership = membership
        _ = try XCTUnwrap(ahead.join(self.memberD.node))

        let changes: [Cluster.MembershipChange] = membership.mergeFrom(incoming: ahead, myself: nil)

        changes.count.shouldEqual(1)
        membership.shouldEqual(self.initialMembership.joining(self.memberD.node))
    }

    internal func test_mergeForward_fromAhead_membership_withMemberNowDown() throws {
        var membership: Cluster.Membership = try Cluster.Membership.parse(
            """
            A.up B.up C.up [leader:C]
            """,
            nodes: self.allNodes
        )

        let ahead: Cluster.Membership = try Cluster.Membership.parse(
            """
            A.down B.up C.up
            """,
            nodes: self.allNodes
        )

        let changes: [Cluster.MembershipChange] = membership.mergeFrom(incoming: ahead, myself: nil)

        changes.count.shouldEqual(1)
        var expected: Cluster.Membership = membership
        _ = expected.mark(self.nodeA, as: .down)
        membership.shouldEqual(expected)
    }

    internal func test_mergeForward_fromAhead_membership_withDownMembers() throws {
        var membership: Cluster.Membership = try Cluster.Membership.parse(
            """
            A.up B.up
            """,
            nodes: self.allNodes
        )

        let ahead: Cluster.Membership = try Cluster.Membership.parse(
            """
            A.down B.up C.down
            """,
            nodes: self.allNodes
        )

        let changes: [Cluster.MembershipChange] = membership.mergeFrom(incoming: ahead, myself: nil)

        changes.count.shouldEqual(1)
        changes.shouldEqual(
            [
                Cluster.MembershipChange(node: self.nodeA, previousStatus: .operational, toStatus: .down)
                // we do not ADD .down members to our view
            ]
        )
        var expected: Cluster.Membership = membership
        _ = expected.mark(self.nodeA, as: .down)
        membership.shouldEqual(expected)
    }

    internal func test_mergeForward_fromAhead_membership_ignoreRemovedWithoutPrecedingDown() throws {
        var membership: Cluster.Membership = try Cluster.Membership.parse(
            "A.up B.up C.up [leader:C]",

            nodes: self.allNodes
        )

        let ahead: Cluster.Membership = try Cluster.Membership.parse(
            "A.removed B.up C.up [leader:C]",

            nodes: self.allNodes
        )

        let changes: [Cluster.MembershipChange] = membership.mergeFrom(incoming: ahead, myself: self.nodeA)

        // removed MUST follow a .down, yet A was never down, so we ignore this.
        changes.shouldEqual([])
    }
}
