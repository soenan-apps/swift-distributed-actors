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

extension Cluster.MembershipGossip {
    /// A table containing information about which node has seen the gossip at which version.
    ///
    /// It is best visualized as a series of views (by "owners" of a row) onto the state of the cluster.
    ///
    /// ```
    /// | A | A:2, B:10, C:2 |
    /// | B | A:2, B:12      |
    /// | C | C:5            |
    /// ```
    ///
    /// E.g. by reading the above table, we can know that:
    /// - node A: has seen some gossips from B, yet is behind by 2 updates on B, it has received early gossip from C
    /// - node B: is the "farthest" along the vector timeline, yet has never seen gossip from C
    /// - node C (we think): has never seen any gossip from either A or B, realistically though it likely has,
    ///   however it has not yet sent a gossip to "us" such that we could have gotten its updated version vector.
    internal struct SeenTable: Equatable, CustomStringConvertible, CustomPrettyStringConvertible {
        internal var underlying: [Cluster.Node: VersionVector]

        internal var nodes: Dictionary<Cluster.Node, VersionVector>.Keys {
            self.underlying.keys
        }

        internal var description: String {
            "Cluster.MembershipGossip.SeenTable(\(self.underlying))"
        }

        internal init() {
            self.underlying = [:]
        }

        internal init(myselfNode: Cluster.Node, version: VersionVector) {
            self.underlying = [myselfNode: version]
        }

        /// If the table does NOT include the `node`, we assume that the `latestVersion` is "more recent than no
        /// information at all."
        ///
        /// - Returns: The `node`'s version's relationship to the latest version.
        ///   E.g. `.happenedBefore` if the latest version is known to be more "recent" than the node's observed
        /// version.
        /// - SeeAlso: The definition of `VersionVector.CausalRelation` for detailed discussion of all possible
        /// relations.
        internal func compareVersion(
            observedOn owner: Cluster.Node,
            to incomingVersion: VersionVector
        ) -> VersionVector.CausalRelation {
            // We know that the node has seen _at least_ the membership at `nodeVersion`.
            (self.underlying[owner] ?? VersionVector()).compareTo(incomingVersion)
        }

        /// Merging an incoming `Cluster.Gossip` into a `Cluster.Gossip.SeenTable` means "progressing (version) time"
        /// for both "us" and the incoming data's owner in "our view" about it.
        ///
        /// In other words, we gained information and our membership has "moved forward".
        ///
        internal mutating func merge(selfOwner: Cluster.Node, incoming: Self) {
            var ownerVersion: VersionVector = self.version(at: selfOwner) ?? VersionVector()

            for incomingNode in incoming.nodes {
                if let incomingVersion = incoming.version(at: incomingNode) {
                    var thatNodeVersion: VersionVector = self.underlying[incomingNode] ?? VersionVector()
                    thatNodeVersion.merge(other: incomingVersion)
                    ownerVersion.merge(other: thatNodeVersion)
                    self.underlying[incomingNode] = thatNodeVersion
                }
            }
            self.underlying[selfOwner] = ownerVersion
        }

        /// Increments a specific ReplicaVersion, in the view owned by the `owner`.
        ///
        /// E.g. if the owner is `A` it may increment its counter in such table:
        /// ```
        /// | A | A:1, B:10 |
        /// +---------------+
        /// | B | A:1, B:12 |
        /// ```
        ///
        /// To obtain `A | A:2, B:10`, after which we know that our view is "ahead or concurrent" because of the
        /// difference
        /// in the A field, meaning we need to gossip with B to converge those two version vectors.
        @discardableResult
        internal mutating func incrementVersion(owner: Cluster.Node, at node: Cluster.Node) -> VersionVector {
            if var version = self.underlying[owner] {
                version.increment(at: .node(node))
                self.underlying[owner] = version
                return version
            }
            // we treat incrementing from "nothing" as creating a new entry
            let version: VersionVector = VersionVector((.node(node), 1))
            self.underlying[owner] = version
            return version
        }

        /// View a version vector at a specific node.
        /// This "view" represents "our" latest information about what we know that node has observed.
        /// This information may (and most likely is) outdated as the nodes continue to gossip to one another.
        internal func version(at node: Cluster.Node) -> VersionVector? {
            self.underlying[node]
        }

        /// Prunes any trace of the passed in node from the seen table.
        /// This includes the version vector that this node may have observed, and also any part of other's version
        /// vectors
        /// where this node was present.
        ///
        /// Performing this operation should be done with great care, as it means that if "the same exact node" were
        /// to "come back" it would be indistinguishable from being a new node. Measures to avoid this from happening
        /// must be taken on the cluster layer, by using and checking for tombstones.
        internal mutating func prune(_ nodeToPrune: Cluster.Node) {
            _ = self.underlying.removeValue(forKey: nodeToPrune)
            let replicaToPrune: ReplicaID = .node(nodeToPrune)

            for (key, version) in self.underlying where version.contains(replicaToPrune, 0) {
                self.underlying[key] = version.pruneReplica(replicaToPrune)
            }
        }

        internal func prettyDescription(depth: Int) -> String {
            var renderedTable: String = "Cluster.Gossip.SeenTable(\n"
            let entryHeadingPadding: String = String(repeating: " ", count: 4 * depth)
            let entryPadding: String = String(repeating: " ", count: 4 * (depth + 1))

            for (node, versions) in underlying.sorted(by: { $0.key < $1.key }) {
                let entryHeader: String = "\(entryHeadingPadding)\(node) observed versions:\n"

                renderedTable.append(entryHeader)
                for (replica, version) in versions.state.sorted(by: { $0.key < $1.key }) {
                    renderedTable.append("\(entryPadding)\(replica) @ \(version)\n")
                }
            }
            renderedTable.append(")")
            return renderedTable
        }
    }
}
