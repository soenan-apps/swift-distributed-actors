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
    /// Special merge function that only moves members "forward" however never removes them, as removal MUST ONLY be
    /// issued specifically by a leader working on the assumption that the `incoming` Membership is KNOWN to be "ahead",
    /// and e.g. if any nodes are NOT present in the incoming membership, they shall be considered `.removed`.
    ///
    /// Otherwise, functions as a normal merge, by moving all members "forward" in their respective lifecycles.
    ///
    /// The following table illustrates the possible state transitions of a node during a merge:
    ///
    /// ```
    /// node's status  | "ahead" node's status                | resulting node's status
    /// ---------------+--------------------------------------|-------------------------
    ///  <none>       -->  [.joining, .operational, .leaving]         --> <ahead status>
    ///  <none>       -->  [.down, .removed]                 --> <none>
    ///  [.joining]   -->  [.joining, .operational, .leaving, .down]  --> <ahead status>
    ///  [.operational]        -->  [.operational, .leaving, .down]            --> <ahead status>
    ///  [.leaving]   -->  [.leaving, .down]                 --> <ahead status>
    ///  [.down]      -->  [.down]                           --> <ahead status>
    ///  [.down]      -->  <none> (if some node removed)     --> <none>
    ///  [.down]      -->  <none> (iff myself node removed)  --> .removed
    ///  <any status> -->  [.removed]**                      --> <none>
    ///
    /// * `.removed` is never stored EXCEPT if the `myself` member has been seen removed by other members of the
    /// cluster.
    /// ** `.removed` should never be gossiped/incoming within the cluster, but if it were to happen it is treated like
    /// a removal.
    ///
    /// Warning: Leaders are not "merged", they get elected by each node (!).
    ///
    /// - Returns: any membership changes that occurred (and have affected the current membership).
    public mutating func mergeFrom(incoming: Cluster.Membership, myself: Cluster.Node?) -> [Cluster.MembershipChange] {
        var changes: [Cluster.MembershipChange] = []

        // Set of nodes whose members are currently .down, and not present in the incoming gossip.
        //
        // as we apply incoming member statuses, remove members from this set
        // if any remain in the set, it means they were removed in the incoming membership
        // since we strongly assume the incoming one is "ahead" (i.e. `self happenedBefore ahead`),
        // we remove these members and emit .removed changes.
        var downNodesToRemove: Set<Cluster.Node> = Set(self.members(withStatus: .down).map(\.node))

        // 1) move forward any existing members or new members according to the `ahead` statuses
        for incomingMember in incoming.membersByNode.values {
            downNodesToRemove.remove(incomingMember.node)

            guard var knownMember = self.membersByNode[incomingMember.node] else {
                // member NOT known locally ----------------------------------------------------------------------------

                // only proceed if the member isn't already on its way out
                guard incomingMember.status < Cluster.MemberStatus.down else {
                    // no need to do anything if it is a removal coming in, yet we already do not know this node
                    continue
                }

                // it is information about a new member, merge it in
                self.membersByNode[incomingMember.node] = incomingMember

                var change: Cluster.MembershipChange = Cluster.MembershipChange(member: incomingMember)
                change.previousStatus = nil  // since "new"
                changes.append(change)
                continue
            }

            // it is a known member ------------------------------------------------------------------------------------
            if let change = knownMember.moveForward(to: incomingMember.status) {
                if change.status.isRemoved {
                    self.membersByNode.removeValue(forKey: incomingMember.node)
                } else {
                    self.membersByNode[incomingMember.node] = knownMember
                }
                changes.append(change)
            }
        }

        // 2) if any nodes we know about locally, were not included in the `ahead` membership
        changes.append(
            contentsOf: downNodesToRemove.compactMap { nodeToRemove in
                if nodeToRemove == myself {
                    // we do NOT remove ourselves completely from our own membership, we remain .removed however
                    return self.mark(nodeToRemove, as: .removed)
                }
                // This is safe since we KNOW the node used to be .down before,
                // and removals are only performed on convergent cluster state.
                // Thus all members in the cluster have seen the node as down, or already removed it.
                // Removal also causes the unique node to be tombstoned in cluster and connections severed,
                // such that it shall never be contacted again.
                //
                // Even if received "old" concurrent gossips with the node still present, we know it would be at-least
                // down, and thus we'd NOT add it to the membership again, due to the `<none> + .down = .<none>` merge
                // rule.
                return self.removeCompletely(nodeToRemove)
            }
        )

        return changes
    }
}
