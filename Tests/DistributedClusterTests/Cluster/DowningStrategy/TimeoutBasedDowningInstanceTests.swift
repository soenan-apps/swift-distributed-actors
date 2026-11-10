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

internal final class TimeoutBasedDowningInstanceTests: XCTestCase {
    private lazy var instance: TimeoutBasedDowningStrategy = .init(.default, selfNode: self.selfNode)

    private let selfNode: Cluster.Node =
        Cluster.Node(endpoint: Cluster.Endpoint(systemName: "Test", host: "localhost", port: 8_888), nid: .random())
    private lazy var selfMember: Cluster.Member = Cluster.Member(node: self.selfNode, status: .operational)

    private let otherNode: Cluster.Node =
        Cluster.Node(endpoint: Cluster.Endpoint(systemName: "Test", host: "localhost", port: 9_999), nid: .random())
    private lazy var otherMember: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)

    private let yetAnotherNode: Cluster.Node =
        Cluster.Node(endpoint: Cluster.Endpoint(systemName: "Test", host: "localhost", port: 2_222), nid: .random())
    private lazy var yetAnotherMember: Cluster.Member = Cluster.Member(node: self.yetAnotherNode, status: .operational)

    private let nonMemberNode: Cluster.Node =
        Cluster.Node(endpoint: Cluster.Endpoint(systemName: "Test", host: "localhost", port: 1_111), nid: .random())
    private lazy var nonMember: Cluster.Member = Cluster.Member(node: self.nonMemberNode, status: .operational)

    override internal func setUp() {
        self.instance = TimeoutBasedDowningStrategy(.default, selfNode: self.selfNode)
    }

    override internal func tearDown() {
        self.instance.membership = .empty
        self.instance.unreachableMembers.removeAll()
        self.instance.pendingDownMembers.removeAll()
        super.tearDown()
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: onLeaderChange

    internal func test_onLeaderChange_whenNotLeaderAndNewLeaderIsSelfAddress_shouldBecomeLeader() throws {
        self.instance.isLeader.shouldBeFalse()
        let directive: DowningStrategyDirective = try self.instance.onLeaderChange(to: self.selfMember)
        // when no nodes are pending to be downed, the directive should be `.unchanged`
        guard case .unchanged = directive.underlying else {
            throw TestError("Expected directive to be .unchanged")
        }
        self.instance.isLeader.shouldBeTrue()
    }

    // FIXME: has to be changed a bit when downing moved to subscribing to Cluster.MembershipChange events
    internal func test_onLeaderChange_whenNotLeaderAndNewLeaderIsOtherAddress_shouldNotBecomeLeader() throws {
        self.instance.isLeader.shouldBeFalse()

        _ = self.instance.membership.join(self.otherNode)
        let directive: DowningStrategyDirective = try self.instance.onLeaderChange(to: self.otherMember)
        // we the node does not become the leader, the directive should be `.unchanged`
        guard case .unchanged = directive.underlying else {
            throw TestError("Expected directive to be .unchanged")
        }
        self.instance.isLeader.shouldBeFalse()
    }

    internal func test_onLeaderChange_whenLeaderAndNewLeaderIsOtherAddress_shouldLoseLeadership() throws {
        _ = self.instance.membership.join(self.selfNode)
        _ = self.instance.membership.join(self.otherNode)

        _ = try self.instance.onLeaderChange(to: self.selfMember)
        self.instance.isLeader.shouldBeTrue()
        let directive: DowningStrategyDirective = try self.instance.onLeaderChange(to: self.otherMember)
        // when losing leadership, the directive should be `.unchanged`
        guard case .unchanged = directive.underlying else {
            throw TestError("Expected directive to be .unchanged")
        }
        self.instance.isLeader.shouldBeFalse()
    }

    internal func test_onLeaderChange_whenLeaderAndNewLeaderIsSelfAddress_shouldStayLeader() throws {
        _ = try self.instance.membership.applyLeadershipChange(to: self.selfMember)
        self.instance.isLeader.shouldBeTrue()
        _ = try self.instance.onLeaderChange(to: self.selfMember)
        self.instance.isLeader.shouldBeTrue()
    }

    internal func test_onLeaderChange_whenLeaderAndNoNewLeaderIsElected_shouldLoseLeadership() throws {
        _ = try self.instance.membership.applyLeadershipChange(to: self.selfMember)
        self.instance.isLeader.shouldBeTrue()
        _ = try self.instance.onLeaderChange(to: nil)
        self.instance.isLeader.shouldBeFalse()
    }

    internal func test_onLeaderChange_whenNotLeaderAndNoNewLeaderIsElected_shouldNotBecomeLeader() throws {
        self.instance.isLeader.shouldBeFalse()
        _ = try self.instance.onLeaderChange(to: nil)
        self.instance.isLeader.shouldBeFalse()
    }

    internal func test_onLeaderChange_whenBecomingLeaderAndNodesPendingToBeDowned_shouldReturnMarkAsDown() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        self.instance.pendingDownMembers.insert(member)
        let directive: DowningStrategyDirective = try self.instance.onLeaderChange(to: self.selfMember)
        guard case .markAsDown(let addresses) = directive.underlying else {
            throw Boom("")
        }
        addresses.count.shouldEqual(1)
        addresses.shouldContain(member)
        self.instance.isLeader.shouldBeTrue()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: onTimeout

    internal func test_onTimeout_whenNotCurrentlyLeader_shouldInsertMemberAddressIntoMarkAsDown() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        self.instance.isLeader.shouldBeFalse()
        self.instance.unreachableMembers.insert(member)
        let directive: DowningStrategyDirective = self.instance.onTimeout(member)

        guard case .unchanged = directive.underlying else {
            throw TestError("Expected directive to be .unchanged")
        }

        self.instance.pendingDownMembers.shouldContain(member)
    }

    internal func test_onTimeout_whenCurrentlyLeader_shouldReturnMarkAsDown() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        _ = try self.instance.membership.applyLeadershipChange(to: self.selfMember)
        self.instance.unreachableMembers.insert(member)
        let directive: DowningStrategyDirective = self.instance.onTimeout(member)

        guard case .markAsDown(let node) = directive.underlying else {
            throw TestError("Expected directive to be .markAsDown")
        }

        node.shouldEqual([member])
    }

    internal func test_onTimeout_shouldNotRetainAlreadyIssuedAsDownMembers() throws {
        _ = self.instance.membership.join(self.selfNode)
        _ = self.instance.membership.join(self.otherNode)
        _ = self.instance.membership.join(self.yetAnotherNode)

        // we are the leader, if a timeout happens, we should issue .down
        _ = try self.instance.onLeaderChange(to: self.selfMember)

        let unreachableMember: Cluster.Member = self.otherMember.asUnreachable

        let directive: DowningStrategyDirective = self.instance.onMemberUnreachable(.init(member: unreachableMember))
        guard case .startTimer = directive.underlying else {
            throw TestError("Expected .startTimer, but got \(directive)")
        }

        let downDecision: DowningStrategyDirective = self.instance.onTimeout(unreachableMember)
        guard case .markAsDown(let nodesToDown) = downDecision.underlying else {
            throw TestError("Expected .markAsDown, but got \(directive)")
        }

        nodesToDown.shouldEqual([unreachableMember])

        // since we signalled the .down, no need to retain the member as "to be marked down" anymore,
        // if we never cleaned that set it could be technically a memory leak, continuing to accumulate
        // all members that we downed over the lifetime of the cluster.
        self.instance.pendingDownMembers.shouldBeEmpty()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: onMemberRemoved

    internal func test_onMemberRemoved_whenMemberWasUnreachable_shouldReturnCancelTimer() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        self.instance.unreachableMembers.insert(member)
        let directive: DowningStrategyDirective = self.instance.onMemberRemoved(member)

        guard case .cancelTimer = directive.underlying else {
            throw TestError("Expected directive to be .cancelTimer")
        }
    }

    internal func test_onMemberRemoved_whenMemberWasMarkAsDown_shouldReturnNone() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        self.instance.pendingDownMembers.insert(member)
        let directive: DowningStrategyDirective = self.instance.onMemberRemoved(member)

        guard case .unchanged = directive.underlying else {
            throw TestError("Expected directive to be .unchanged")
        }
    }

    internal func test_onMemberRemoved_whenMemberNotKnown_shouldReturnNone() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        let directive: DowningStrategyDirective = self.instance.onMemberRemoved(member)

        guard case .unchanged = directive.underlying else {
            throw TestError("Expected directive to be .unchanged")
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: onMemberReachable

    internal func test_onMemberReachable_whenMemberWasUnreachable_shouldReturnCancelTimer() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        self.instance.unreachableMembers.insert(member)
        let directive: DowningStrategyDirective = self.instance.onMemberReachable(.init(member: member.asUnreachable))

        guard case .cancelTimer = directive.underlying else {
            throw TestError("Expected directive to be .cancelTimer")
        }
    }

    internal func test_onMemberReachable_whenMemberWasMarkAsDown_shouldReturnNone() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        self.instance.pendingDownMembers.insert(member)
        let directive: DowningStrategyDirective = self.instance.onMemberReachable(.init(member: member.asUnreachable))

        guard case .unchanged = directive.underlying else {
            throw TestError("Expected directive to be .unchanged")
        }
    }

    internal func test_onMemberReachable_whenMemberNotKnown_shouldReturnNone() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        let directive: DowningStrategyDirective = self.instance.onMemberReachable(.init(member: member.asUnreachable))

        guard case .unchanged = directive.underlying else {
            throw TestError("Expected directive to be .unchanged")
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: onMemberUnreachable

    internal func test_onMemberUnreachable_shouldAddAddressOfMemberToUnreachableSet() throws {
        let member: Cluster.Member = Cluster.Member(node: self.otherNode, status: .operational)
        guard
            case .startTimer = self.instance.onMemberUnreachable(
                .init(member: member.asUnreachable)
            ).underlying
        else {
            throw TestError("Expected directive to be .startTimer")
        }
        self.instance.unreachableMembers.shouldContain(member.asUnreachable)
    }
}
