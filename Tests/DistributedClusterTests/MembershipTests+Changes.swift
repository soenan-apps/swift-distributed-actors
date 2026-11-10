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
    internal func test_membership_equality() {
        let left: Cluster.Membership = [
            Cluster.Member(node: self.memberA.node, status: .operational, upNumber: 1),
            Cluster.Member(node: self.memberB.node, status: .operational, upNumber: 1),
            Cluster.Member(node: self.memberC.node, status: .operational, upNumber: 1),
        ]
        let right: Cluster.Membership = [
            Cluster.Member(node: self.memberA.node, status: .operational, upNumber: 1),
            Cluster.Member(node: self.memberB.node, status: .down, upNumber: 1),
            Cluster.Member(node: self.memberC.node, status: .operational, upNumber: 1),
        ]

        left.shouldNotEqual(right)
        right.shouldNotEqual(left)  // soundness check, since hand implemented equality
    }

    internal func test_member_equality() {
        // member identity is the underlying unique node, this status DOES NOT contribute to equality:
        var member: Cluster.Member = self.memberA
        member.status = .down
        member.shouldEqual(self.memberA)

        // addresses are different
        self.memberA.shouldNotEqual(self.memberB)

        // only the node id is different:
        let one: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: "firstA",
                    host: "1.1.1.1",
                    port: 1_111
                ),
                nid: .init(1)
            ),
            status: .operational
        )
        let two: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: "firstA",
                    host: "1.1.1.1",
                    port: 1_111
                ),
                nid: .init(12_222)
            ),
            status: .operational
        )
        one.shouldNotEqual(two)

        // node names do not matter for equality:
        let three: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: "does",
                    host: "1.1.1.1",
                    port: 1_111
                ),
                nid: .init(1)
            ),
            status: .operational
        )
        let four: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: "not matter",
                    host: "1.1.1.1",
                    port: 1_111
                ),
                nid: .init(12_222)
            ),
            status: .operational
        )
        three.shouldNotEqual(four)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Member lookups

    internal func test_member_replacement_shouldOfferChange() throws {
        var membership: Cluster.Membership = [self.memberA, self.memberB]
        let secondReplacement: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: self.nodeB.systemName,
                    host: self.nodeB.host,
                    port: self.nodeB.port
                ),
                nid: .random()
            ),
            status: .operational
        )

        let change: Cluster.MembershipChange = try XCTUnwrap(
            membership.applyMembershipChange(
                Cluster.MembershipChange(member: secondReplacement)
            )
        )
        change.isReplacement.shouldBeTrue()
        change.member.shouldEqual(secondReplacement)
        change.replacementDownPreviousNodeChange.shouldEqual(
            Cluster.MembershipChange(member: self.memberB, toStatus: .down)
        )

        membership.members(atLeast: .joining).count.shouldEqual(3)
        membership.members(atLeast: .down).count.shouldEqual(1)
        let memberNode: Cluster.Member? = membership.member(change.member.node)
        memberNode?.status.shouldEqual(Cluster.MemberStatus.operational)
    }

    // ====
    // ----------------------------------------------------------------------------------------------------------------
    // MARK: Applying changes

    internal func test_apply_LeadershipChange() throws {
        var membership: Cluster.Membership = self.initialMembership
        membership.isLeader(self.memberA).shouldBeFalse()

        let change: Cluster.LeadershipChange? = try membership.applyLeadershipChange(to: self.memberA)
        change.shouldEqual(Cluster.LeadershipChange(oldLeader: nil, newLeader: self.memberA))
        membership.isLeader(self.memberA).shouldBeTrue()

        // applying "same change" no-op
        let noChange: Cluster.LeadershipChange? = try membership.applyLeadershipChange(to: self.memberA)
        noChange.shouldBeNil()

        // changing to no leader is ok
        let noLeaderChange: Cluster.LeadershipChange? = try membership.applyLeadershipChange(to: nil)
        noLeaderChange.shouldEqual(Cluster.LeadershipChange(oldLeader: self.memberA, newLeader: nil))

        do {
            _ = try membership.applyLeadershipChange(to: self.memberD)  // not part of membership (!)
        } catch {
            "\(error)".shouldStartWith(prefix: "MembershipError(nonMemberLeaderSelected")
        }
    }

    // what if leadership change oldLeader also implies the oldLeader -> .down

    internal func test_join_memberReplacement() throws {
        var membership: Cluster.Membership = self.initialMembership

        let replacesFirstNode: Cluster.Node = Cluster.Node(endpoint: self.nodeA.endpoint, nid: .random())

        let change: Cluster.MembershipChange = try XCTUnwrap(membership.join(replacesFirstNode))

        change.isReplacement.shouldBeTrue()
        change.replaced.shouldEqual(self.memberA)
        try XCTUnwrap(change.replaced).status.shouldEqual(self.memberA.status)
        change.node.shouldEqual(replacesFirstNode)
        change.status.shouldEqual(.joining)
    }

    internal func test_apply_memberReplacement_withUpNode() throws {
        var membership: Cluster.Membership = self.initialMembership

        let firstReplacement: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: self.nodeA.endpoint,
                nid: .init(111_111)
            ),
            status: .operational
        )

        let changeToApply: Cluster.MembershipChange = Cluster.MembershipChange(member: firstReplacement)
        guard let change = membership.applyMembershipChange(changeToApply) else {
            throw TestError("Expected a change, but didn't get one")
        }

        change.isReplacement.shouldBeTrue()
        change.replaced.shouldEqual(self.memberA)
        try XCTUnwrap(change.replaced).status.shouldEqual(self.memberA.status)
        change.node.shouldEqual(firstReplacement.node)
        change.status.shouldEqual(firstReplacement.status)
    }

    internal func test_apply_withNodeNotPartOfClusterAnymore_leaving() throws {
        var membership: Cluster.Membership = self.initialMembership
        _ = membership.removeCompletely(self.memberC.node)

        let changeToApply: Cluster.MembershipChange = Cluster.MembershipChange(member: self.memberC, toStatus: .leaving)
        if let change = membership.applyMembershipChange(changeToApply) {
            throw TestError("Expected no change, since memberC was already removed from membership; was: \(change)")
        }
    }

    internal func test_apply_withNodeNotPartOfClusterAnymore_down() throws {
        var membership: Cluster.Membership = self.initialMembership
        _ = membership.removeCompletely(self.memberC.node)

        let changeToApply: Cluster.MembershipChange = Cluster.MembershipChange(member: self.memberC, toStatus: .down)
        if let change = membership.applyMembershipChange(changeToApply) {
            throw TestError("Expected no change, since memberC was already removed from membership; was: \(change)")
        }
    }

    internal func test_apply_memberRemoval() throws {
        var membership: Cluster.Membership = self.initialMembership

        let removal: Cluster.Member = Cluster.Member(node: self.memberA.node, status: .removed)

        guard let change = membership.applyMembershipChange(Cluster.MembershipChange(member: removal)) else {
            throw TestError("Expected a change, but didn't get one")
        }

        change.isReplacement.shouldBeFalse()
        change.node.shouldEqual(removal.node)
        change.status.shouldEqual(removal.status)

        membership.member(self.memberA.node).shouldBeNil()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: member listing

    internal func test_members_listing() {
        self.initialMembership.members(atLeast: .joining).count.shouldEqual(3)
        self.initialMembership.members(atLeast: .operational).count.shouldEqual(3)
        var changed: Cluster.Membership = self.initialMembership
        _ = changed.mark(self.memberA.node, as: .down)
        changed.count(atLeast: .joining).shouldEqual(3)
        changed.count(atLeast: .operational).shouldEqual(3)
        changed.count(atLeast: .leaving).shouldEqual(1)
        changed.count(atLeast: .down).shouldEqual(1)
        changed.count(atLeast: .removed).shouldEqual(0)
    }

    internal func test_members_listing_filteringByReachability() {
        var changed: Cluster.Membership = self.initialMembership
        _ = changed.mark(self.memberA.node, as: .down)

        _ = changed.mark(self.memberA.node, reachability: .unreachable)
        _ = changed.mark(self.memberB.node, reachability: .unreachable)

        // exact status match

        changed.members(withStatus: .joining).count.shouldEqual(0)
        changed.members(withStatus: .operational).count.shouldEqual(2)
        changed.members(withStatus: .down).count.shouldEqual(1)
        changed.members(withStatus: .leaving).count.shouldEqual(0)
        changed.members(withStatus: .removed).count.shouldEqual(0)

        changed.members(withStatus: .joining, reachability: .reachable).count.shouldEqual(0)
        changed.members(withStatus: .operational, reachability: .reachable).count.shouldEqual(1)
        changed.members(withStatus: .down, reachability: .reachable).count.shouldEqual(0)
        changed.members(withStatus: .leaving, reachability: .reachable).count.shouldEqual(0)
        changed.members(withStatus: .removed, reachability: .reachable).count.shouldEqual(0)

        changed.members(withStatus: .joining, reachability: .unreachable).count.shouldEqual(0)
        changed.members(withStatus: .operational, reachability: .unreachable).count.shouldEqual(1)
        changed.members(withStatus: .down, reachability: .unreachable).count.shouldEqual(1)
        changed.members(withStatus: .leaving, reachability: .unreachable).count.shouldEqual(0)
        changed.members(withStatus: .removed, reachability: .unreachable).count.shouldEqual(0)

        // at-least status match

        changed.members(atLeast: .joining, reachability: .reachable).count.shouldEqual(1)
        changed.members(atLeast: .operational, reachability: .reachable).count.shouldEqual(1)
        changed.members(atLeast: .down, reachability: .reachable).count.shouldEqual(0)
        changed.members(atLeast: .leaving, reachability: .reachable).count.shouldEqual(0)
        changed.members(atLeast: .removed, reachability: .reachable).count.shouldEqual(0)

        changed.members(atLeast: .joining, reachability: .unreachable).count.shouldEqual(2)
        changed.members(atLeast: .operational, reachability: .unreachable).count.shouldEqual(2)
        changed.members(atLeast: .leaving, reachability: .unreachable).count.shouldEqual(1)
        changed.members(atLeast: .down, reachability: .unreachable).count.shouldEqual(1)
        changed.members(atLeast: .removed, reachability: .unreachable).count.shouldEqual(0)
    }

    // ====
    // ----------------------------------------------------------------------------------------------------------------
    // MARK: Marking
}
