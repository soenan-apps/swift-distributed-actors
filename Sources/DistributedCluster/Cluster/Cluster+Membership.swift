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

extension Cluster {
    /// Represents the set of members of this cluster.
    ///
    /// Membership changes are driven by nodes joining and leaving the cluster.
    /// Leaving the cluster may be graceful or triggered by a failure detector.
    ///
    /// ### Replacement (Unique) Nodes
    /// A node (or member) is referred to as a "replacement" if it shares _the same_ protocol+host+address (i.e.
    /// ``Cluster/Endpoint``),
    /// with another member; It MAY join "over" an existing node and will immediately cause the previous node to be
    /// marked ``Cluster/MemberStatus/down``
    /// upon such transition. Such situations can take place when an actor system node is terminated and started on the
    /// same host+port immediately,
    /// and attempts to connect to the same cluster as its previous "incarnation". Such situation is called a
    /// replacement, and by the assumption
    /// of that it should not be possible to run many nodes on exact same host+port the previous node is immediately
    /// ejected and marked down.
    ///
    /// ### Member state transitions
    /// Members can only move "forward" along their status lifecycle, refer to ``Cluster/MemberStatus``
    /// docs for a diagram of legal transitions.
    public struct Membership: ExpressibleByArrayLiteral {

        /// Initialize an empty membership (with no members).
        public static var empty: Cluster.Membership {
            .init(members: [])
        }

        /// Members MUST be stored `Cluster.Node` rather than plain node, since there may exist "replacements" which we
        /// need
        /// to track gracefully -- in order to tell all other nodes that those nodes are now down/leaving/removed, if a
        /// node took their place. This makes lookup by `Node` not nice, but realistically, that lookup is quite rare --
        /// only
        /// when operator issued moves are induced e.g. "> down 1.1.1.1:3333", since operators do not care about
        /// `Cluster.Node.Identifier` most of the time.
        internal var membersByNode: [Cluster.Node: Cluster.Member]

        /// Count of all members (regardless of their `MemberStatus`)
        public var count: Int {
            self.membersByNode.count
        }

        // ====
        // ------------------------------------------------------------------------------------------------------------
        // MARK: Leaders

        /// A leader is a specific ``Cluster/Member`` which was selected to fulfil the leadership role for the time
        /// being.
        ///
        /// A leader returning a non-nil value, guarantees that the same ``Cluster/Member`` existing as part of this
        /// ``Cluster/Membership`` as well (non-members cannot be leaders).
        ///
        /// Clustering offered by this project does not really designate any "special" nodes; yet sometimes a leader may
        /// be useful to make decisions more efficient or centralized.
        /// Leaders may be selected using various strategies, the most simple one being sorting members by their
        /// addresses and picking the "lowest".
        ///
        /// ### Leaders in partitions
        /// There CAN be multiple leaders in the same cluster, in face of cluster partitions,
        /// where certain parts of the cluster mark other groups as unreachable.
        ///
        /// Certain actions can only be performed by the "leader" of a group.
        public internal(set) var leader: Cluster.Member? {
            get {
                self.leaderNode.flatMap { member($0) }
            }
            set {
                self.leaderNode = newValue?.node
            }
        }

        internal var leaderNode: Cluster.Node?

        /// Returns a copy of the membership, though without any leaders assigned.
        public var leaderless: Cluster.Membership {
            var members: Self = self
            members.leader = nil
            return members
        }

        /// Initialize a membership with the given members.
        public init(members: [Cluster.Member]) {
            self.membersByNode = Dictionary(minimumCapacity: members.count)
            for member in members {
                self.membersByNode[member.node] = member
            }
        }

        /// Initializes membership from an array literal of members.
        public init(arrayLiteral members: Cluster.Member...) {
            self.init(members: members)
        }

        // ====
        // ------------------------------------------------------------------------------------------------------------
        // MARK: Members

        /// Retrieves a `Member` by its `Cluster.Node`.
        ///
        /// This operation is guaranteed to return a member if it was added to the membership UNLESS the member has been
        /// `.removed`
        /// and dropped which happens only after an extended period of time.
        public func member(_ node: Cluster.Node) -> Cluster.Member? {
            self.membersByNode[node]
        }

        /// Picks "first", in terms of least progressed among its lifecycle member in presence of potentially multiple
        /// members
        /// for a non-unique `Node`. In practice, this happens when an existing node is superseded by a "replacement",
        /// and the
        /// previous node becomes immediately down.
        public func anyMember(forEndpoint endpoint: Cluster.Endpoint) -> Cluster.Member? {
            self.membersByNode.values.sorted(by: Cluster.MemberStatus.lifecycleOrdering).first { member in
                member.node.endpoint == endpoint
            }
        }

        /// Returns the most recently promoted member, if any.
        public func youngestMember() -> Cluster.Member? {
            self.members(atLeast: .joining).max(by: Cluster.Member.ageOrdering)
        }

        /// Returns the oldest promoted member, if any.
        public func oldestMember() -> Cluster.Member? {
            self.members(atLeast: .joining).min(by: Cluster.Member.ageOrdering)
        }

        /// More efficient than using ``members(atLeast:reachability:)`` followed by a `.count`
        public func count(atLeast status: Cluster.MemberStatus) -> Int {
            self.membersByNode.values
                .lazy
                .filter { member in status <= member.status }
                .count
        }

        /// More efficient than using ``members(atMost:reachability:)`` followed by a `.count`
        public func count(atMost status: Cluster.MemberStatus) -> Int {
            self.membersByNode.values
                .lazy
                .filter { member in member.status <= status }
                .count
        }

        /// More efficient than using `members(withStatus:)` followed by a `.count`
        public func count(withStatus status: Cluster.MemberStatus) -> Int {
            self.membersByNode.values
                .lazy
                .filter { member in status == member.status }
                .count
        }

        /// Returns all members that are part of this membership, and have the exact `status` and `reachability` status.
        ///
        ///
        /// - Parameters:
        ///   - status: status for which to check the members for
        ///   - reachability: optional reachability that is the members will be filtered by
        /// - Returns: array of members matching those checks. Can be empty.
        public func members(
            withStatus status: Cluster.MemberStatus, reachability: Cluster.MemberReachability? = nil
        ) -> [Cluster.Member] {
            self.members(withStatus: [status], reachability: reachability)
        }

        /// Returns all members that are part of this membership, and have the any ``Cluster/MemberStatus`` that is part
        /// of the `statuses` passed in and `reachability` status.
        ///
        /// - Parameters:
        ///   - statuses: statuses for which to check the members for
        ///   - reachability: optional reachability that is the members will be filtered by
        /// - Returns: array of members matching those checks. Can be empty.
        public func members(
            withStatus statuses: Set<Cluster.MemberStatus>, reachability: Cluster.MemberReachability? = nil
        ) -> [Cluster.Member] {
            let reachabilityFilter: (Cluster.Member) -> Bool = { member in
                reachability == nil || member.reachability == reachability
            }
            return self.membersByNode.values.filter { member in
                statuses.contains(member.status) && reachabilityFilter(member)
            }
        }

        /// Returns all members that are part of this membership, and have the any ``Cluster/MemberStatus`` that is *at
        /// least*
        /// the passed in `status` passed in and `reachability` status. See ``Cluster/MemberStatus`` to learn more about
        /// the meaning of "at least".
        ///
        /// - Parameters:
        ///   - status: status for which to check the members for
        ///   - reachability: optional reachability that is the members will be filtered by
        /// - Returns: array of members matching those checks. Can be empty.
        public func members(
            atLeast status: Cluster.MemberStatus, reachability: Cluster.MemberReachability? = nil
        ) -> [Cluster.Member] {
            if status == .joining, reachability == nil {
                return Array(self.membersByNode.values)
            }

            let reachabilityFilter: (Cluster.Member) -> Bool = { member in
                reachability == nil || member.reachability == reachability
            }
            return self.membersByNode.values.filter { member in
                status <= member.status && reachabilityFilter(member)
            }
        }

        /// Returns all members that are part of this membership, and have ``Cluster/MemberStatus`` that is *at most*
        /// the passed in `status` and `reachability`. See ``Cluster/MemberStatus`` to learn more about the meaning of
        /// "at most".
        ///
        /// - Parameters:
        ///   - status: "at most" status for which to check the members for
        ///   - reachability: optional reachability that the members will be filtered by
        /// - Returns: array of members matching those checks. Can be empty.
        public func members(
            atMost status: Cluster.MemberStatus, reachability: Cluster.MemberReachability? = nil
        ) -> [Cluster.Member] {
            if status == .removed, reachability == nil {
                return Array(self.membersByNode.values)
            }

            let reachabilityFilter: (Cluster.Member) -> Bool = { member in
                reachability == nil || member.reachability == reachability
            }
            return self.membersByNode.values.filter { member in
                member.status <= status && reachabilityFilter(member)
            }
        }

        /// Find specific member, identified by its unique node identity.
        public func member(byUniqueNodeID nid: Cluster.Node.Identifier) -> Cluster.Member? {
            self.membersByNode.first { $0.key.nid == nid }?.value
        }

        /// Checks if passed in node is the leader (given the current view of the cluster state by this Membership).
        public func isLeader(_ node: Cluster.Node) -> Bool {
            self.leader?.node == node
        }

        /// Checks if passed in node is the leader (given the current view of the cluster state by this Membership).
        public func isLeader(_ member: Cluster.Member) -> Bool {
            self.isLeader(member.node)
        }

        /// Checks if the membership contains a member representing this ``Cluster.Node``.
        internal func contains(_ node: Cluster.Node) -> Bool {
            self.membersByNode[node] != nil
        }
    }
}
