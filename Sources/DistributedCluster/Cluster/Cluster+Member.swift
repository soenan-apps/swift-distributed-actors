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
    /// A participating cluster node, identified only by its underlying `Node`.
    public struct Member: Hashable, CustomStringConvertible, CustomDebugStringConvertible {
        /// Orders members by the sequence assigned when the leader made them operational.
        public static let ageOrdering: (Cluster.Member, Cluster.Member) -> Bool = { lhs, rhs in
            (lhs.upNumber ?? 0) < (rhs.upNumber ?? 0)
        }

        /// Orders members by their node addresses, consistently selecting the lowest address first.
        public static let lowestAddressOrdering: (Cluster.Member, Cluster.Member) -> Bool = { lhs, rhs in
            lhs.node < rhs.node
        }

        /// Unique node of this cluster member.
        public let node: Cluster.Node

        /// Logical lifecycle status, independent of failure-detector reachability.
        public var status: Cluster.MemberStatus

        /// Failure-detector assessment; a down or removed member may still be reachable.
        public var reachability: Cluster.MemberReachability

        /// Sequence assigned when the leader made the member operational; absent before that transition.
        public var upNumber: Int?

        /// A copy marked unreachable by the failure detector.
        public var asUnreachable: Self {
            var member: Self = self
            member.reachability = .unreachable
            return member
        }

        /// A copy marked reachable by the failure detector.
        public var asReachable: Self {
            var member: Self = self
            member.reachability = .reachable
            return member
        }

        /// Marks the member down without moving a down or removed member backwards in its lifecycle.
        public var asDownIfNotAlready: Self {
            switch self.status {
            case .joining, .operational, .leaving, .nonExhaustive:
                return Self(node: self.node, status: .down)

            case .down, .removed:
                return self
            }
        }

        public var description: String {
            "Member(\(self.node), status: \(self.status), reachability: \(self.reachability))"
        }

        public var debugDescription: String {
            let sequenceDescription: String = self.upNumber.map { ", _upNumber: \($0)" } ?? ""
            return """
            Member(\(String(reflecting: self.node)), status: \(self.status), \
            reachability: \(self.reachability)\(sequenceDescription))
            """
        }

        /// Creates a member with reachable failure-detector state and no assigned sequence.
        public init(node: Cluster.Node, status: Cluster.MemberStatus) {
            self.node = node
            self.status = status
            self.upNumber = nil
            self.reachability = .reachable
        }

        internal init(node: Cluster.Node, status: Cluster.MemberStatus, upNumber: Int) {
            assert(
                !status.isJoining,
                """
                Node \(node) was \(status) yet was given upNumber: \(upNumber). \
                Only at-least operational members may have upNumbers!
                """
            )
            self.node = node
            self.status = status
            self.upNumber = upNumber
            self.reachability = .reachable
        }

        public static func == (lhs: Cluster.Member, rhs: Cluster.Member) -> Bool {
            lhs.node == rhs.node
        }

        public func hash(into hasher: inout Hasher) {
            self.node.hash(into: &hasher)
        }

        /// Advances the lifecycle, returning a change only for a valid forward transition.
        /// Removal is permitted only directly from the down state.
        public mutating func moveForward(to status: Cluster.MemberStatus) -> Cluster.MembershipChange? {
            guard self.status < status else {
                return nil
            }
            if status == .removed {
                if self.status == .down {
                    defer { self.status = .removed }
                    return .init(member: self, toStatus: .removed)
                }
                return nil
            }

            defer { self.status = status }
            return Cluster.MembershipChange(member: self, toStatus: status)
        }

        /// Returns a copy with the requested valid forward lifecycle transition applied.
        public func movingForward(to status: MemberStatus) -> Self {
            var member: Self = self
            _ = member.moveForward(to: status)
            return member
        }
    }
}
