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

import Logging
import NIO

extension Leadership {
    /// Simple strategy which does not require any additional coordination from members to select a leader.
    ///
    /// All `MemberStatus.joining`, `MemberStatus.operational` _reachable_ members are sorted by their addresses,
    /// and the "lowest" is selected as the leader.
    ///
    /// Only REACHABLE nodes are taken into account. This means that in a situation with a cluster partition,
    /// there WILL be multiple leaders. In this coordination free scheme, this is needed in order to avoid "getting
    /// stuck",
    /// without a leader to perform the unreachable -> down move.
    ///
    /// ### Use cases
    /// This strategy works well for non critical tasks, which nevertheless benefit from performing them more centrally
    /// than either by all nodes at once, or by random nodes.
    ///
    /// ### Guarantees & discussion
    /// - Given at-least `minimumNumberOfMembersToDecide` members are present in the membership, is always able to
    /// select a leader.
    ///   - Even if all members are unreachable, we always have "this member", which by definition always is reachable.
    /// - The `minimumNumberOfMembersToDecide` is used to delay moving members to `.operational` until the cluster has
    /// at least
    ///   the given number of nodes available. This is useful to only start clustered features or signal readiness once
    /// the cluster
    ///   has enough nodes connected to absorb the anticipated incoming traffic (or ready from a correctness
    /// perspective, of at least
    ///   having a few nodes to fallback to).
    ///
    /// - Does NOT guarantee global leader uniqueness!
    ///   - As the leader is decided strictly based on the known list of members and their reachability status, its
    ///     correctness relies on this membership being "complete", i.e. if used in a partitioned cluster, where nodes
    /// `[a, b, c]`,
    ///     all see each other as _reachable_, however view nodes `[x, y]` as _unreachable_ (as marked by e.g. SWIM
    /// failure detection),
    ///     then this leader election will result in `a` being the leader in one side of the partition, and potentially
    /// `x` as the leader
    ///     in the other "side" of the partition.
    ///   - This can be advantageous -- perhaps a leader on each side should be responsible if the "side" of a partition
    ///     should better terminate itself as it is the "smaller side of a partition" and may prefer to terminate
    ///     rather than risk data corruption if the nodes `x, y` continued writing data.
    ///
    /// #### Mode: loseLeadershipIfBelowMinNrOfMembers
    /// By default, leadership is elected e.g. among 5 nodes, and if the count of the membership's reachable nodes
    /// falls below `minimumNrOfMembers` the leader _remains_ being the leader (unless the node which became unreachable
    /// is the leader itself). This allows for a more stable leadership in face of flaky other nodes.
    ///
    /// If you prefer the leader to give up its leadership whenever there is less than `minimumNrOfMembers` reachable
    /// members, you may set `loseLeadershipIfBelowMinNrOfMembers` to true. Meaning that the leader will only be
    /// fulfilling this role whenever the minimum number of nodes exist. This may be useful when operation would
    /// potentially be unsafe given less than `minimumNrOfMembers` nodes.
    ///
    public struct LowestReachableMember: LeaderElection {
        // guarantees, and you should consider using another scheme or consensus based modes.
        internal let minimumNumberOfMembersToDecide: Int
        internal let loseLeadershipIfBelowMinNrOfMembers: Bool

        /// - param minimumNrOfMembers: minimum number of REACHABLE members when a leader can be elected.
        public init(minimumNrOfMembers: Int, loseLeadershipIfBelowMinNrOfMembers: Bool = false) {
            self.minimumNumberOfMembersToDecide = minimumNrOfMembers
            self.loseLeadershipIfBelowMinNrOfMembers = loseLeadershipIfBelowMinNrOfMembers
        }

        public mutating func runElection(
            context: LeaderElectionContext,
            membership snapshot: Cluster.Membership
        ) -> LeaderElectionResult {
            var membership: Cluster.Membership = snapshot
            let membersToSelectAmong: [Cluster.Member] = membership.members(
                atMost: .operational,
                reachability: .reachable
            )

            let enoughMembers: Bool = membersToSelectAmong.count >= self.minimumNumberOfMembersToDecide
            if enoughMembers {
                return self.selectByLowestAddress(
                    context: context,
                    membership: &membership,
                    membersToSelectAmong: membersToSelectAmong
                )
            }
            context.log.info(
                """
                Not enough members [\(membersToSelectAmong.count)/\(self.minimumNumberOfMembersToDecide)] \
                to run election, members: \(membersToSelectAmong)
                """
            )
            if self.loseLeadershipIfBelowMinNrOfMembers {
                return self.notEnoughMembers(
                    context: context,
                    membership: &membership,
                    membersToSelectAmong: membersToSelectAmong
                )
            }
            return self.belowMinMembersTryKeepStableLeader(context: context, membership: &membership)
        }

        internal mutating func notEnoughMembers(
            context: LeaderElectionContext,
            membership: inout Cluster.Membership,
            membersToSelectAmong: [Cluster.Member]
        ) -> LeaderElectionResult {
            // not enough members to make a decision yet
            context.log.trace(
                """
                Not enough members to select leader from, minimum nr of members \
                [\(membersToSelectAmong.count)/\(self.minimumNumberOfMembersToDecide)]
                """
            )

            if let currentLeader = membership.leader {
                // Clear current leader and trigger `Cluster.LeadershipChange`
                // swiftlint:disable:next force_try
                let change: Cluster.LeadershipChange? = try! membership.applyLeadershipChange(to: nil)
                context.log.trace("Removing leader [\(currentLeader)]")
                return .init(context.loop.next().makeSucceededFuture(change))
            }
            return .init(context.loop.next().makeSucceededFuture(nil))
        }

        /// Attempts to keep the leadership stable (i.e. even if other nodes become unreachable, the leader can still
        /// potentially remain the same).
        ///
        /// We can do so if:
        /// - a leader was elected previously
        /// - it still is reachable and part of the membership
        ///
        /// Other nodes MAY NOT be elected, as we are below the minimum members threshold, we can only keep an existing
        /// leader, but not elect new ones.
        internal mutating func belowMinMembersTryKeepStableLeader(
            context: LeaderElectionContext,
            membership: inout Cluster.Membership
        ) -> LeaderElectionResult {
            guard let currentLeader = membership.leader else {
                // there was no leader previously, and now we are below `minimumNumberOfMembersToDecide` thus cannot
                // select a new one
                return .init(context.loop.next().makeSucceededFuture(nil))  // no change
            }

            guard currentLeader.status <= .operational else {
                // the leader is not up anymore, and we have to remove it (cannot keep trusting it)
                // swiftlint:disable:next force_try
                let change: Cluster.LeadershipChange? = try! membership.applyLeadershipChange(to: nil)
                context.log.trace("Removing leader [\(currentLeader)], not enough members to elect new leader.")
                return .init(context.loop.next().makeSucceededFuture(change))
            }

            // the leader is still up, regardless of reachability, we still trust it;
            // as we do not have enough members to do another election, we stick to the node we know.
            return .init(context.loop.next().makeSucceededFuture(nil))
        }

        internal mutating func selectByLowestAddress(
            context: LeaderElectionContext,
            membership: inout Cluster.Membership,
            membersToSelectAmong: [Cluster.Member]
        ) -> LeaderElectionResult {
            let oldLeader: Cluster.Member? = membership.leader

            // select the leader, by lowest address
            let leader: Cluster.Member? = membersToSelectAmong.min(by: Cluster.Member.lowestAddressOrdering)

            // swiftlint:disable:next force_try
            if let change = try! membership.applyLeadershipChange(to: leader) {
                context.log.debug(
                    "Selected new leader: [\(oldLeader, orElse: "nil") -> \(leader, orElse: "nil")]",
                    metadata: [
                        "membership": "\(membership)"
                    ]
                )
                return .init(context.loop.next().makeSucceededFuture(change))
            }
            return .init(context.loop.next().makeSucceededFuture(nil))
        }

    }
}
