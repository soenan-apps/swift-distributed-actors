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

extension Cluster.Membership: Hashable {

    public static func == (lhs: Cluster.Membership, rhs: Cluster.Membership) -> Bool {
        guard lhs.leaderNode == rhs.leaderNode else {
            return false
        }
        guard lhs.membersByNode.count == rhs.membersByNode.count else {
            return false
        }
        for (lNode, lMember) in lhs.membersByNode {
            if let rMember = rhs.membersByNode[lNode],
                lMember.node != rMember.node
                    || lMember.status != rMember.status
                    || lMember.reachability != rMember.reachability {
                return false
            }
        }

        return true
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.leaderNode)
        for member in self.membersByNode.values {
            hasher.combine(member.node)
            hasher.combine(member.status)
            hasher.combine(member.reachability)
        }
    }
}
