// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

/// The `TimeoutBasedDowningStrategy` marks nodes that have been unreachable as `.down` after a configurable timeout.
///
/// Only the node that is currently the currently assigned leader can make the decision to mark another node as down.
/// Non-leading nodes will keep track of the nodes they would have marked down and do so in case they become leader.
/// If a node becomes reachable again before the timeout expires, it will not be considered for downing anymore.
public final class TimeoutBasedDowningStrategy: DowningStrategy {
    internal let settings: TimeoutBasedDowningStrategySettings
    internal let selfNode: Cluster.Node

    internal var membership: Cluster.Membership

    internal var isLeader: Bool {
        self.membership.isLeader(self.selfNode)
    }

    // unreachable members will be marked down after the timeout expires
    internal var unreachableMembers: Set<Cluster.Member>

    // buffer for nodes that will be marked down, if this node becomes the leader
    internal var pendingDownMembers: Set<Cluster.Member>

    internal init(_ settings: TimeoutBasedDowningStrategySettings, selfNode: Cluster.Node) {
        self.settings = settings
        self.selfNode = selfNode
        self.unreachableMembers = []
        self.pendingDownMembers = []
        self.membership = .empty
    }

    public func onClusterEvent(event: Cluster.Event) throws -> DowningStrategyDirective {
        switch event {
        case .snapshot(let snapshot):
            self.membership = snapshot
            return .unchanged

        case .membershipChange(let change):
            guard let appliedChange = self.membership.applyMembershipChange(change) else {
                return .unchanged
            }

            if appliedChange.isAtLeast(.down) {
                // it was marked as down by someone, we don't need to track it anymore
                _ = self.pendingDownMembers.remove(appliedChange.member)
                _ = self.unreachableMembers.remove(appliedChange.member)
                return .cancelTimer(member: appliedChange.member)
            }
            if let replaced = appliedChange.replaced {
                _ = self.pendingDownMembers.remove(replaced)
                _ = self.unreachableMembers.remove(replaced)
                return .markAsDown(members: [replaced])
            }

            return .unchanged

        case .leadershipChange(let change):
            return try self.onLeaderChange(to: change.newLeader)

        case .reachabilityChange(let change):
            if change.toUnreachable {
                return self.onMemberUnreachable(change)
            }
            return self.onMemberReachable(change)

        case .nonExhaustive:
            return .unchanged  // do nothing
        }
    }

    public func onTimeout(_ member: Cluster.Member) -> DowningStrategyDirective {
        guard let nodeToDown = self.unreachableMembers.remove(member) else {
            return .unchanged  // perhaps we removed it already for other reasons (e.g. node replacement)
        }
        if self.isLeader {
            return .markAsDown(members: [nodeToDown])
        }
        self.pendingDownMembers.insert(nodeToDown)
        return .unchanged
    }

    internal func onMemberUnreachable(_ change: Cluster.ReachabilityChange) -> DowningStrategyDirective {
        _ = self.membership.applyReachabilityChange(change)
        let member: Cluster.Member = change.member

        self.unreachableMembers.insert(member)

        return .startTimer(member: member, delay: self.settings.downUnreachableMembersAfter)
    }

    internal func onMemberReachable(_ change: Cluster.ReachabilityChange) -> DowningStrategyDirective {
        _ = self.membership.applyReachabilityChange(change)
        let member: Cluster.Member = change.member

        _ = self.pendingDownMembers.remove(member)
        if self.unreachableMembers.remove(member) != nil {
            return .cancelTimer(member: member)
        }

        return .unchanged
    }

    internal func onLeaderChange(to leader: Cluster.Member?) throws -> DowningStrategyDirective {
        _ = try self.membership.applyLeadershipChange(to: leader)

        if self.isLeader, !self.pendingDownMembers.isEmpty {
            defer { self.pendingDownMembers = [] }
            return .markAsDown(members: self.pendingDownMembers)
        }
        return .unchanged
    }

    internal func onMemberRemoved(_ member: Cluster.Member) -> DowningStrategyDirective {
        self.pendingDownMembers.remove(member)

        if self.unreachableMembers.remove(member) != nil {
            return .cancelTimer(member: member)
        }

        return .unchanged
    }
}
