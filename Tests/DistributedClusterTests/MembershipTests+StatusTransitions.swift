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
    internal func test_moveForward_MemberStatus() {
        var member: Cluster.Member = self.memberA
        member.status = .joining
        let joiningMember: Cluster.Member = member

        member.status = .operational
        let upMember: Cluster.Member = member

        member.status = .leaving
        let leavingMember: Cluster.Member = member
        member.status = .down
        let downMember: Cluster.Member = member
        member.status = .removed

        member.status = .joining
        member.moveForward(to: .operational).shouldEqual(
            Cluster.MembershipChange(
                member: joiningMember,
                toStatus: .operational
            )
        )
        member.status.shouldEqual(.operational)
        member.moveForward(to: .joining).shouldEqual(nil)  // no change, cannot move back

        member.moveForward(to: .operational).shouldEqual(nil)  // no change, cannot move to same status
        member.moveForward(to: .leaving).shouldEqual(Cluster.MembershipChange(member: upMember, toStatus: .leaving))
        member.status.shouldEqual(.leaving)

        member.moveForward(to: .joining).shouldEqual(nil)  // no change, cannot move back
        member.moveForward(to: .operational).shouldEqual(nil)  // no change, cannot move back
        member.moveForward(to: .leaving).shouldEqual(nil)  // no change, same
        member.moveForward(to: .down).shouldEqual(Cluster.MembershipChange(member: leavingMember, toStatus: .down))
        member.status.shouldEqual(.down)

        member.moveForward(to: .joining).shouldEqual(nil)  // no change, cannot move back
        member.moveForward(to: .operational).shouldEqual(nil)  // no change, cannot move back
        member.moveForward(to: .leaving).shouldEqual(nil)  // no change, cannot move back
        member.moveForward(to: .down).shouldEqual(nil)  // no change, same
        member.moveForward(to: .removed).shouldEqual(Cluster.MembershipChange(member: downMember, toStatus: .removed))
        member.status.shouldEqual(.removed)

        member.status = .joining
        member.moveForward(to: .leaving).shouldEqual(
            Cluster.MembershipChange(
                member: joiningMember,
                toStatus: .leaving
            )
        )
        member.status.shouldEqual(.leaving)

        member.status = .joining
        member.moveForward(to: .down).shouldEqual(Cluster.MembershipChange(member: joiningMember, toStatus: .down))
        member.status.shouldEqual(.down)

        assertRemovalRequiresDownState(&member, downMember: downMember)
    }

    private func assertRemovalRequiresDownState(_ member: inout Cluster.Member, downMember: Cluster.Member) {
        // moving to removed is only allowed from .down
        member.status = .joining
        member.moveForward(to: .removed).shouldBeNil()
        member.status.shouldEqual(.joining)

        member.status = .operational
        member.moveForward(to: .removed).shouldBeNil()
        member.status.shouldEqual(.operational)

        member.status = .leaving
        member.moveForward(to: .removed).shouldBeNil()
        member.status.shouldEqual(.leaving)

        member.status = .down
        member.moveForward(to: .removed).shouldEqual(Cluster.MembershipChange(member: downMember, toStatus: .removed))
        member.status.shouldEqual(.removed)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Diffing

    internal func test_membershipDiff_beEmpty_whenNothingChangedForIt() {
        let changed: Cluster.Membership = self.initialMembership
        let diff: MembershipDiff = Cluster.Membership.difference(from: self.initialMembership, to: changed)
        diff.changes.count.shouldEqual(0)
    }

    internal func test_membershipDiff_shouldIncludeEntry_whenStatusChangedForIt() throws {
        let changed: Cluster.Membership = self.initialMembership.marking(self.memberA.node, as: .leaving)

        let diff: MembershipDiff = Cluster.Membership.difference(from: self.initialMembership, to: changed)

        diff.changes.count.shouldEqual(1)
        let diffEntry: Cluster.MembershipChange = try XCTUnwrap(diff.changes.first)
        diffEntry.node.shouldEqual(self.memberA.node)
        diffEntry.previousStatus?.shouldEqual(.operational)
        diffEntry.status.shouldEqual(.leaving)
    }

    internal func test_membershipDiff_shouldIncludeEntry_whenMemberRemoved() throws {
        let changed: Cluster.Membership = self.initialMembership.removingCompletely(self.memberA.node)

        let diff: MembershipDiff = Cluster.Membership.difference(from: self.initialMembership, to: changed)

        diff.changes.count.shouldEqual(1)
        let diffEntry: Cluster.MembershipChange = try XCTUnwrap(diff.changes.first)
        diffEntry.node.shouldEqual(self.memberA.node)
        diffEntry.previousStatus?.shouldEqual(.operational)
        diffEntry.status.shouldEqual(.removed)
    }

    internal func test_membershipDiff_shouldIncludeEntry_whenMemberAdded() throws {
        let changed: Cluster.Membership = self.initialMembership.joining(self.memberD.node)

        let diff: MembershipDiff = Cluster.Membership.difference(from: self.initialMembership, to: changed)

        diff.changes.count.shouldEqual(1)
        let diffEntry: Cluster.MembershipChange = try XCTUnwrap(diff.changes.first)
        diffEntry.node.shouldEqual(self.memberD.node)
        diffEntry.previousStatus.shouldBeNil()
        diffEntry.status.shouldEqual(.joining)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Merge Memberships
}
