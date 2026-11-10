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

extension Cluster {
    /// Gossip payload about members in the cluster.
    ///
    /// Used to guarantee phrases like "all nodes have seen a node A in status S", upon which the Leader may act.
    internal struct MembershipGossip: Codable, Equatable, CustomPrettyStringConvertible {
        internal let owner: Cluster.Node
        /// A table maintaining our perception of other nodes views on the version of membership.
        /// Each row in the table represents what versionVector we know the given node has observed recently.
        /// It may have in the mean time of course observed a new version already.
        internal var seen: Cluster.MembershipGossip.SeenTable

        // Would be Payload of the generic envelope.
        /// IMPORTANT: Whenever the membership is updated with an effective change, we MUST move the version forward (!)
        internal var membership: Cluster.Membership

        /// The version vector of this gossip and its membership state.
        internal var version: VersionVector {
            guard let ownerVersion = self.seen.underlying[self.owner] else {
                preconditionFailure("Membership gossip must retain its owner's seen version")
            }
            return ownerVersion
        }

        internal init(ownerNode: Cluster.Node) {
            self.owner = ownerNode
            self.seen = Cluster.MembershipGossip.SeenTable(myselfNode: ownerNode, version: VersionVector())

            // The actual payload
            self.membership = .empty  // MUST be empty, as on the first "self gossip, we cause all ClusterEvents
        }

        /// Bumps the version via the owner.
        internal mutating func incrementOwnerVersion() {
            self.seen.incrementVersion(owner: self.owner, at: self.owner)
        }

        internal func incrementingOwnerVersion() -> Self {
            var gossip: Self = self
            gossip.seen.incrementVersion(owner: self.owner, at: self.owner)
            return gossip
        }

        /// Merge an incoming gossip _into_ the current gossip.
        /// Ownership of this gossip is retained, versions are bumped, and membership is merged.
        internal mutating func mergeForward(incoming receivedGossip: Self) -> MergeDirective {
            var incoming: Self = receivedGossip

            // 1) decide the relationship between this gossip and the incoming one
            let causalRelation: VersionVector.CausalRelation = self.version.compareTo(incoming.version)

            // 1.1) Protect the node from any gossip from a .down node (!), it cannot and MUST NOT be trusted.
            let incomingGossipOwnerKnownLocally: Cluster.Member? = self.membership.member(incoming.owner)
            guard let incomingOwnerMember = incoming.membership.member(incoming.owner) else {
                return .init(causalRelation: causalRelation, effectiveChanges: [])
            }
            switch incomingGossipOwnerKnownLocally {
            case .some(let locallyKnownMember) where locallyKnownMember.status.isDown:
                // we have NOT removed it yet, but it is down, so we ignore it
                return .init(causalRelation: causalRelation, effectiveChanges: [])

            case .none where incomingOwnerMember.status.isAtLeast(.down):
                // we have likely removed it, and it is down anyway, so we ignore it completely
                return .init(causalRelation: causalRelation, effectiveChanges: [])

            default:
                ()  // ok, so it is fine and still alive
            }

            // 1.2) Protect from zombies: Any nodes that we know are dead or down, we should not accept any information
            // from
            let incomingConcurrentDownMembers: [Cluster.Member] = incoming.membership.members(atLeast: .down)
            for pruneFromIncomingBeforeMerge in incomingConcurrentDownMembers
            where self.membership.member(pruneFromIncomingBeforeMerge.node) == nil {
                _ = incoming.pruneMember(pruneFromIncomingBeforeMerge)
            }

            // 2) calculate membership changes; if this gossip is strictly more recent than the incoming one,
            // we can skip this as we "know" that we already know everything that the incoming has to offer
            // (optimization)
            let changes: [MembershipChange]
            if case .happenedAfter = causalRelation {
                // ignore all changes >>
                // our local view happened strictly _after_ the incoming one, thus it is guaranteed
                // it will not provide us with new information; This is only an optimization, and would work correctly
                // without it.
                changes = []
            } else {
                // incoming is concurrent, ahead, or same
                changes = self.membership.mergeFrom(incoming: incoming.membership, myself: self.owner)
            }

            self.seen.merge(selfOwner: self.owner, incoming: incoming.seen)

            // 3) if any removals happened, we need to prune the removed nodes from the seen table
            for change in changes
            where change.status.isRemoved && change.member.node != self.owner {
                self.seen.prune(change.member.node)
            }

            return .init(causalRelation: causalRelation, effectiveChanges: changes)
        }

        /// Remove member from `membership` and prune the seen tables of any trace of the removed node.
        internal mutating func pruneMember(_ member: Member) -> Cluster.MembershipChange? {
            self.seen.prune(member.node)  // always prune is okey
            return self.membership.removeCompletely(member.node)
        }

        /// Checks for convergence of the membership (seen table) among members.
        ///
        /// ### Convergence
        /// Convergence means that "all (considered) members" have seen at-least the version that the convergence
        /// is checked against (this version). In other words, if a member is seen as `.joining` in this version
        /// other members are guaranteed to have seen this information, or their membership may have progressed further
        /// e.g. the member may have already moved to `.operational` or further in their perception.
        ///
        /// Only `.operational` and `.leaving` members are considered, since joining members are "too early"
        /// to matter in decisions, and down members shall never participate in decision making.
        internal func converged() -> Bool {
            let members: [Cluster.Member] = self.membership.members(withStatus: [.joining, .operational, .leaving])
            let requiredVersion: VersionVector = self.version

            if members.isEmpty {
                return true  // no-one is around disagree with me! }:-)
            }

            let laggingBehindMemberFound: Bool = members.contains { member in
                if let memberSeenVersion = seen.version(at: member.node) {
                    switch memberSeenVersion.compareTo(requiredVersion) {
                    case .happenedBefore, .concurrent:
                        return true  // found an offending member, it is lagging behind, thus no convergence

                    case .happenedAfter, .same:
                        return false
                    }
                } else {
                    // Without the member's version, treat it as behind.
                    return true
                }
            }

            return !laggingBehindMemberFound
        }
    }
}
