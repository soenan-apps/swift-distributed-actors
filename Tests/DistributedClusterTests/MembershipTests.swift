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

// Shared fixtures are used by test extensions in separate files.
// swiftlint:disable test_case_accessibility

internal final class MembershipTests: XCTestCase {
    internal let memberA: Cluster.Member = Cluster.Member(
        node: Cluster.Node(
            endpoint: Cluster.Endpoint(
                systemName: "nodeA",
                host: "1.1.1.1",
                port: 1_111
            ),
            nid: .random()
        ),
        status: .operational
    )
    internal var nodeA: Cluster.Node { self.memberA.node }

    internal let memberB: Cluster.Member = Cluster.Member(
        node: Cluster.Node(
            endpoint: Cluster.Endpoint(
                systemName: "nodeB",
                host: "2.2.2.2",
                port: 2_222
            ),
            nid: .random()
        ),
        status: .operational
    )
    internal var nodeB: Cluster.Node { self.memberB.node }

    internal let memberC: Cluster.Member = Cluster.Member(
        node: Cluster.Node(
            endpoint: Cluster.Endpoint(
                systemName: "nodeC",
                host: "3.3.3.3",
                port: 3_333
            ),
            nid: .random()
        ),
        status: .operational
    )
    internal var nodeC: Cluster.Node { self.memberC.node }

    internal let memberD: Cluster.Member = Cluster.Member(
        node: Cluster.Node(
            endpoint: Cluster.Endpoint(
                systemName: "nodeD",
                host: "4.4.4.4",
                port: 4_444
            ),
            nid: .random()
        ),
        status: .operational
    )
    internal var nodeD: Cluster.Node { self.memberD.node }

    internal lazy var allNodes: [Cluster.Node] = [
        nodeA, nodeB, nodeC,
    ]

    internal lazy var initialMembership: Cluster.Membership = [
        memberA, memberB, memberC,
    ]
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: status ordering

    internal func test_status_ordering() {
        Cluster.MemberStatus.joining.shouldBeLessThanOrEqual(.joining)
        Cluster.MemberStatus.joining.shouldBeLessThan(.operational)
        Cluster.MemberStatus.joining.shouldBeLessThan(.down)
        Cluster.MemberStatus.joining.shouldBeLessThan(.leaving)
        Cluster.MemberStatus.joining.shouldBeLessThan(.removed)

        Cluster.MemberStatus.operational.shouldBeLessThanOrEqual(.operational)
        Cluster.MemberStatus.operational.shouldBeLessThan(.down)
        Cluster.MemberStatus.operational.shouldBeLessThan(.leaving)
        Cluster.MemberStatus.operational.shouldBeLessThan(.removed)

        Cluster.MemberStatus.leaving.shouldBeLessThanOrEqual(.leaving)
        Cluster.MemberStatus.leaving.shouldBeLessThan(.down)
        Cluster.MemberStatus.leaving.shouldBeLessThan(.removed)

        Cluster.MemberStatus.down.shouldBeLessThanOrEqual(.down)
        Cluster.MemberStatus.down.shouldBeLessThan(.removed)

        Cluster.MemberStatus.removed.shouldBeLessThanOrEqual(.removed)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: age ordering

    internal func test_age_ordering() {
        let milliseconds: [Cluster.Member] = [
            Cluster.Member(node: self.memberA.node, status: .joining),
            Cluster.Member(node: self.memberA.node, status: .operational, upNumber: 1),
            Cluster.Member(node: self.memberA.node, status: .down, upNumber: 4),
            Cluster.Member(node: self.memberA.node, status: .operational, upNumber: 2),
        ]
        let nanoseconds: [Int?] = milliseconds.sorted(by: Cluster.Member.ageOrdering).map(\.upNumber)
        nanoseconds.shouldEqual([nil, 1, 2, 4])
    }

    // ====
    // ----------------------------------------------------------------------------------------------------------------
    // MARK: equality

    // Implementation note:
    // See the Membership equality implementation for an in depth rationale why the equality works like this.

}
// swiftlint:enable test_case_accessibility
