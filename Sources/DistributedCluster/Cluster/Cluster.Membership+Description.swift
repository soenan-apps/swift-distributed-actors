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

extension Cluster.Membership: CustomStringConvertible, CustomDebugStringConvertible, CustomPrettyStringConvertible {
    /// Pretty multi-line output of a membership, useful for manual inspection
    public var prettyDescription: String {
        var res: String = "leader: \(self.leader, orElse: ".none")"
        for member in self.membersByNode.values.sorted(by: { $0.node.endpoint.port < $1.node.endpoint.port }) {
            res += """
                \n  \(reflecting: member.node) status \
                [\(member.status.rawValue, leftPadTo: Cluster.MemberStatus.maxStrLen)]
                """
        }
        return res
    }

    public var description: String {
        """
        Membership(count: \(self.count), leader: \(self.leader, orElse: ".none"), \
        members: \(self.membersByNode.values))
        """
    }

    public var debugDescription: String {
        """
        Membership(count: \(self.count), leader: \(self.leader, orElse: ".none"), \
        members: \(self.membersByNode.values))
        """
    }
}
