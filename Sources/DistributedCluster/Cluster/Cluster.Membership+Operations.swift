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

extension Cluster.Membership {
    /// Interpret and apply passed in membership change as the appropriate join/leave/down action.
    ///
    /// Applying a new node status that becomes a "replacement" of an existing member, returns a
    /// `Cluster.MembershipChange` that is a "replacement".
    ///
    /// - Returns: the resulting change that was applied to the membership; note that this may be `nil`,
    ///   if the change did not cause any actual change to the membership state (e.g. signaling a join of the same node
    /// twice).
    public mutating func applyMembershipChange(_ change: Cluster.MembershipChange) -> Cluster.MembershipChange? {
        if case .removed = change.status {
            return self.removeCompletely(change.node)
        }

        if let knownUnique = self.member(change.node) {
            // it is known uniquely, so we just update its status
            return self.mark(knownUnique.node, as: change.status)
        }

        if change.isAtLeast(.leaving) {
            // if the *specific node* is not part of membership yet, and we're performing an leaving/down/removal,
            // there is nothing else to be done here; a replacement potentially already exists, and we should not modify
            // it.
            return nil
        }

        if let previousMember = self.anyMember(forEndpoint: change.node.endpoint) {
            // we are joining "over" an existing incarnation of a node; causing the existing node to become .down
            // immediately
            if previousMember.status < .down {
                _ = self.mark(previousMember.node, as: .down)
            } else {
                // The replacement event handles the down notifications.
                _ = self.removeCompletely(previousMember.node)
            }
            self.membersByNode[change.node] = change.member

            // emit a replacement membership change, this will cause down cluster events for previous member
            return .init(replaced: previousMember, by: change.member)
        }
        // node is normally joining
        self.membersByNode[change.member.node] = change.member
        return change
    }

    /// Applies a leadership change, marking the new leader the passed in member.
    ///
    /// If the change causes no change in leadership (e.g. the passed in `leader` already is the `self.leader`),
    /// this function will return `nil`. It is guaranteed that if a non-nil value is returned, the old leader is
    /// different from the new leader.
    ///
    /// - Throws: `Cluster.MembershipError` when attempt is made to mark a non-member as leader. First add the leader as
    /// member, then promote it.
    public mutating func applyLeadershipChange(to leader: Cluster.Member?) throws -> Cluster.LeadershipChange? {
        guard let wannabeLeader = leader else {
            if let oldLeader = self.leader {
                // no more leader
                self.leader = nil
                return Cluster.LeadershipChange(oldLeader: oldLeader, newLeader: self.leader)
            }
            // old leader was nil, and new one as well: no change
            return nil
        }

        // for single node "cluster" we allow becoming the leader myself eagerly (e.g. useful in testing)
        if self.membersByNode.isEmpty {
            _ = self.join(wannabeLeader.node)
        }

        // we soundness check that the wanna-be leader is already a member
        guard self.membersByNode[wannabeLeader.node] != nil else {
            throw Cluster.MembershipError(
                .nonMemberLeaderSelected(self, wannabeLeader: wannabeLeader),
                file: #fileID,
                line: #line
            )
        }

        if self.leader == wannabeLeader {
            return nil  // no change was made
        }
        // in other cases, nil or not, we change the leader
        let oldLeader: Cluster.Member? = self.leader
        self.leader = wannabeLeader
        return Cluster.LeadershipChange(oldLeader: oldLeader, newLeader: wannabeLeader)
    }

    /// Alias for `applyLeadershipChange(to:)`
    public mutating func applyLeadershipChange(
        _ change: Cluster.LeadershipChange?
    ) throws -> Cluster.LeadershipChange? {
        try self.applyLeadershipChange(to: change?.newLeader)
    }

    /// - Returns: the changed member if the change was a transition (unreachable -> reachable, or back),
    ///            or `nil` if the reachability is the same as already known by the membership.
    public mutating func applyReachabilityChange(_ change: Cluster.ReachabilityChange) -> Cluster.Member? {
        self.mark(change.member.node, reachability: change.member.reachability)
    }

    /// Returns the change; e.g. if we replaced a node the change `from` will be populated and perhaps a connection
    /// should
    /// be closed to that now-replaced node, since we have replaced it with a new node.
    public mutating func join(_ node: Cluster.Node) -> Cluster.MembershipChange? {
        var change: Cluster.MembershipChange = .init(member: .init(node: node, status: .joining))
        change.previousStatus = nil
        return self.applyMembershipChange(change)
    }

    /// Returns a copy with the node joined, including any resulting replacement transition.
    public func joining(_ node: Cluster.Node) -> Cluster.Membership {
        var membership: Cluster.Membership = self
        _ = membership.join(node)
        return membership
    }

    /// Marks the `Cluster.Member` identified by the `node` with the `status`.
    ///
    /// Handles replacement nodes properly, by emitting a "replacement" change, and marking the replaced node as
    /// `MemberStatus.down`.
    ///
    /// If the membership not aware of this address the update is treated as a no-op.
    public mutating func mark(_ node: Cluster.Node, as status: Cluster.MemberStatus) -> Cluster.MembershipChange? {
        if let existingExactMember = self.member(node) {
            guard existingExactMember.status < status else {
                // this would be a "move backwards" which we do not do; membership only moves forward
                return nil
            }

            var updatedMember: Cluster.Member = existingExactMember
            updatedMember.status = status
            if status == .operational {
                updatedMember.upNumber = self.youngestMember()?.upNumber ?? 1
            }
            self.membersByNode[existingExactMember.node] = updatedMember

            return Cluster.MembershipChange(member: existingExactMember, toStatus: status)
        }
        if let beingReplacedMember = self.anyMember(forEndpoint: node.endpoint) {
            // We did not get a member by exact Cluster.Node match, but we got one by Node match...
            // this means this new node that we are trying to mark is a "replacement" and the `beingReplacedNode` must
            // be .downed!

            // We do not check the "only move forward rule" as this is a NEW node, and is replacing
            // the current one, whichever phase it was in -- perhaps it was .operational, and we're replacing it with a
            // .joining one.
            // This still means that the current `.operational` one is very likely down already just that we have not
            // noticed _yet_.

            // replacement:
            let replacedMember: Cluster.Member = Cluster.Member(node: beingReplacedMember.node, status: .down)
            let nodeD: Cluster.Member = Cluster.Member(node: node, status: status)
            self.membersByNode[replacedMember.node] = replacedMember
            self.membersByNode[nodeD.node] = nodeD

            return Cluster.MembershipChange(replaced: beingReplacedMember, by: nodeD)
        }
        // no such member -> no change applied
        return nil
    }

    /// Returns new membership while marking an existing member with the specified status.
    ///
    /// If the membership not aware of this node the update is treated as a no-op.
    public func marking(_ node: Cluster.Node, as status: Cluster.MemberStatus) -> Cluster.Membership {
        var membership: Cluster.Membership = self
        _ = membership.mark(node, as: status)
        return membership
    }

    /// Mark node with passed in `reachability`
    ///
    /// - Returns: the changed member if the reachability was different than the previously stored one.
    public mutating func mark(_ node: Cluster.Node, reachability: Cluster.MemberReachability) -> Cluster.Member? {
        guard var member = self.membersByNode.removeValue(forKey: node) else {
            // no such member
            return nil
        }

        if member.reachability == reachability {
            // no change
            self.membersByNode[node] = member
            return nil
        }
        // change reachability and return it
        member.reachability = reachability
        self.membersByNode[node] = member
        return member
    }

    /// REMOVES (as in, completely, without leaving even a tombstone or `.down` marker) a `Member` from the
    /// `Membership`.
    /// If the membership is not aware of this member this is treated as no-op.
    ///
    /// - Warning: When removing nodes from cluster one MUST also prune the seen tables (!) of the gossip.
    ///            Rather than calling this function directly, invoke `Cluster.Gossip.removeMember()` which performs all
    /// needed cleanups.
    public mutating func removeCompletely(_ node: Cluster.Node) -> Cluster.MembershipChange? {
        if let member = self.membersByNode[node] {
            self.membersByNode.removeValue(forKey: node)
            return .init(member: member, toStatus: .removed)
        }
        return nil
    }

    /// Returns new membership while removing an existing member, identified by the passed in node.
    public func removingCompletely(_ node: Cluster.Node) -> Cluster.Membership {
        var membership: Cluster.Membership = self
        _ = membership.removeCompletely(node)
        return membership
    }
}
