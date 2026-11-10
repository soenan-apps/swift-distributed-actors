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
    /// Compute a diff between two membership states.
    internal static func difference(from source: Cluster.Membership, to target: Cluster.Membership) -> MembershipDiff {
        var entries: [Cluster.MembershipChange] = []
        entries.reserveCapacity(Swift.max(source.membersByNode.count, target.membersByNode.count))

        var remaining: Cluster.Membership = target

        // iterate over the original member set, and remove from the `to` set any seen members
        for member in source.membersByNode.values {
            if let toMember = remaining.member(member.node) {
                remaining.membersByNode.removeValue(forKey: member.node)
                if member.status != toMember.status {
                    entries.append(.init(member: member, toStatus: toMember.status))
                }
            } else {
                // member is not present `to`, thus it was removed
                entries.append(.init(member: member, toStatus: .removed))
            }
        }

        // any remaining `to` members, are new members
        for member in remaining.membersByNode.values {
            entries.append(.init(node: member.node, previousStatus: nil, toStatus: member.status))
        }

        return MembershipDiff(changes: entries)
    }
}
