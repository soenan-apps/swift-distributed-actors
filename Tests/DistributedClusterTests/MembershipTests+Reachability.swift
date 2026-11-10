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
    internal func test_mark_shouldOnlyProceedForwardInStatuses() throws {
        let member: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: "System",
                    host: "4.4.4.4",
                    port: 1_001
                ),
                nid: .random()
            ),
            status: .joining
        )

        var membership: Cluster.Membership = [member]

        // marking no-member -> no-op

        let noChange: Cluster.MembershipChange? = membership.mark(member.node, as: .joining)
        noChange.shouldBeNil()  // already joining

        let change1: Cluster.MembershipChange? = membership.mark(member.node, as: .operational)
        change1.shouldNotBeNil()

        // testing string output as well as field on purpose
        // as if the fromStatus is not set we may infer it from other places; but in such change, we definitely want it
        // in the `from`
        change1?.previousStatus.shouldEqual(.joining)
        change1?.status.shouldEqual(.operational)
        try "\(XCTUnwrap(change1))".shouldContain("1001 :: [joining] -> [     up]")

        membership.mark(member.node, as: .joining).shouldBeNil()  // can't move "back"
        membership.mark(member.node, as: .operational).shouldBeNil()  // don't move to "same"

        let change2: Cluster.MembershipChange? = membership.mark(member.node, as: .down)
        change2.shouldNotBeNil()
        change2?.previousStatus.shouldEqual(.operational)
        change2?.status.shouldEqual(.down)
        try "\(XCTUnwrap(change2))".shouldContain("1001 :: [     up] -> [   down]")

        membership.mark(member.node, as: .joining).shouldBeNil()  // can't move "back"
        membership.mark(member.node, as: .operational).shouldBeNil()  // can't move "back", from down
    }

    internal func test_mark_shouldNotReturnChangeForMarkingAsSameStatus() {
        let member: Cluster.Member = self.memberA
        var membership: Cluster.Membership = [member]

        let noChange: Cluster.MembershipChange? = membership.mark(member.node, as: member.status)
        noChange.shouldBeNil()
    }

    internal func test_mark_reachability() throws {
        let member: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: "System",
                    host: "4.4.4.4",
                    port: 1_001
                ),
                nid: .random()
            ),
            status: .joining
        )

        var membership: Cluster.Membership = [member]
        membership.mark(member.node, reachability: .reachable).shouldEqual(nil)  // no change

        let res1: Cluster.Member? = membership.mark(member.node, reachability: .unreachable)
        try XCTUnwrap(res1).reachability.shouldEqual(.unreachable)

        membership.mark(member.node, reachability: .unreachable).shouldEqual(nil)  // no change
        _ = membership.mark(member.node, reachability: .unreachable)
    }

    // ====
    // ----------------------------------------------------------------------------------------------------------------
    // MARK: Replacements

    internal func test_join_overAnExistingNode_replacement() throws {
        var membership: Cluster.Membership = self.initialMembership
        let secondReplacement: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: self.nodeB.endpoint,
                nid: .random()
            ),
            status: .joining
        )
        let change: Cluster.MembershipChange = try XCTUnwrap(membership.join(secondReplacement.node))
        change.isReplacement.shouldBeTrue()

        let members: [Cluster.Member] = membership.members(atLeast: .joining)
        var secondDown: Cluster.Member = self.memberB
        secondDown.status = .down

        members.count.shouldEqual(4)
        members.shouldContain(secondReplacement)
        members.shouldContain(secondDown)  // replaced node should be .down
    }

    internal func test_mark_replacement() throws {
        var membership: Cluster.Membership = [self.memberA]

        let firstReplacement: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: self.nodeA.endpoint,
                nid: .random()
            ),
            status: .operational
        )

        guard let change = membership.mark(firstReplacement.node, as: firstReplacement.status) else {
            throw TestError("Expected a change")
        }
        change.isReplacement.shouldBeTrue()
        change.replaced.shouldEqual(self.memberA)
        change.previousStatus.shouldEqual(.operational)
        change.node.shouldEqual(firstReplacement.node)
        change.status.shouldEqual(.operational)
    }

    internal func test_mark_status_whenReplacingWithNewNode() throws {
        let one: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: "System",
                    host: "1.1.1.1",
                    port: 1_001
                ),
                nid: .random()
            ),
            status: .joining
        )
        var two: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: "System",
                    host: "2.2.2.2",
                    port: 2_222
                ),
                nid: .random()
            ),
            status: .operational
        )
        let twoReplacement: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(
                    systemName: "System",
                    host: "2.2.2.2",
                    port: 2_222
                ),
                nid: .random()
            ),
            status: .joining
        )

        var membership: Cluster.Membership = [one, two]

        let changed: Cluster.MembershipChange = try XCTUnwrap(membership.mark(twoReplacement.node, as: .joining))
        changed.member.node.shouldEqual(twoReplacement.node)
        changed.status.isJoining.shouldBeTrue()

        two.status = .down
        membership.shouldEqual(
            [
                one, two,
                twoReplacement,
            ]
        )  // `twoReplacement` replacement remains joining; is unchanged by mark performed to `two`
    }

    internal func test_replacement_changeCreation() throws {
        var existing: Cluster.Member = self.memberA
        existing.status = .joining

        let replacement: Cluster.Member = Cluster.Member(
            node: Cluster.Node(
                endpoint: existing.node.endpoint,
                nid: .random()
            ),
            status: .operational
        )

        let change: Cluster.MembershipChange = Cluster.MembershipChange(replaced: existing, by: replacement)
        change.isReplacement.shouldBeTrue()

        change.member.shouldEqual(replacement)
        change.node.shouldEqual(replacement.node)
        change.previousStatus.shouldEqual(existing.status)

        try XCTUnwrap(change.replaced).status.shouldEqual(
            existing.status
        )  // though we have the replaced member, it will have its own previous status
        change.replaced.shouldEqual(existing)

        change.isUp.shouldBeTrue()  // up is the status of the replacement
    }

    // ====
    // ----------------------------------------------------------------------------------------------------------------
    // MARK: Moving members along their lifecycle

}
