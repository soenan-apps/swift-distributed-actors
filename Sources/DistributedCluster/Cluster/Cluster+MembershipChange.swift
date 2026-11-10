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
    /// Represents a membership change received from gossip or originating from a local decision,
    /// or originating from local joining and downing decisions.
    public struct MembershipChange: Hashable, CustomStringConvertible {
        /// Current member that is part of the membership after this change
        public internal(set) var member: Member

        /// The node which the change concerns.
        public var node: Cluster.Node {
            self.member.node
        }

        /// Only set if the change is a "replacement", which can happen only if a node joins
        /// from the same physical address (host + port), however its UID has changed.
        internal private(set) var replaced: Member?

        /// A new node on the same host and port replaces the old node, which must be assumed down.
        internal var replacementDownPreviousNodeChange: Self? {
            guard let replacedMember = self.replaced else {
                return nil
            }
            return .init(member: replacedMember, toStatus: .down)
        }

        /// Status before the change, if the member was previously known.
        public internal(set) var previousStatus: MemberStatus?
        /// Status after the change.
        public let status: MemberStatus

        /// Is a "replace" operation, meaning a new node with different UID has replaced a previousNode.
        /// This can happen upon a service reboot, with stable network address -- the new node then "replaces" the old
        /// one,
        /// and the old node shall be removed from the cluster as a result of this.
        public var isReplacement: Bool {
            self.replaced != nil
        }

        /// Whether the change enters the joining state.
        public var isJoining: Bool {
            self.status.isJoining
        }

        /// Whether the change enters the up state.
        public var isUp: Bool {
            self.status.isUp
        }

        /// Whether the change enters the down state.
        public var isDown: Bool {
            self.status.isDown
        }

        /// Whether the change enters the leaving state.
        public var isLeaving: Bool {
            self.status.isLeaving
        }

        /// Whether this change removes the member.
        public var isRemoval: Bool {
            self.status.isRemoved
        }

        public var description: String {
            let base: String
            if let replaced = self.replaced {
                base = "[replaced:\(reflecting: replaced)] by \(reflecting: self.node)"
            } else {
                base = "\(reflecting: self.node)"
            }
            return """
            \(base) :: \
            [\(self.previousStatus?.rawValue ?? "unknown", leftPadTo: Cluster.MemberStatus.maxStrLen)] \
            -> [\(self.status.rawValue, leftPadTo: Cluster.MemberStatus.maxStrLen)]
            """
        }

        internal init(member: Member) {
            self.init(member: member, toStatus: nil)
        }

        internal init(member: Member, toStatus: MemberStatus?) {
            self.replaced = nil
            if let targetStatus = toStatus {
                var changedMember: Member = member
                changedMember.status = targetStatus
                self.member = changedMember
                self.previousStatus = member.status
                self.status = targetStatus
            } else {
                self.member = member
                self.previousStatus = nil
                self.status = member.status
            }
        }

        internal init(node: Cluster.Node, previousStatus: MemberStatus?, toStatus: MemberStatus) {
            self.member = .init(node: node, status: toStatus)
            self.replaced = nil
            self.previousStatus = previousStatus
            self.status = toStatus
        }

        /// Replaces a member with a new identity at the same host and port.
        internal init(replaced: Member, by newMember: Member) {
            let replacementMessage: String = """
                Replacement Cluster.MembershipChange should be for same non-unique node; \
                Was: \(replaced), and \(newMember)
                """
            assert(replaced.node.host == newMember.node.host, replacementMessage)
            assert(replaced.node.port == newMember.node.port, replacementMessage)
            assert(
                newMember.status != .down,
                "Attempted to replace a member \(replaced) with a .down member: \(newMember)! This should never happen."
            )

            self.replaced = replaced
            self.member = newMember
            self.previousStatus = replaced.status
            self.status = newMember.status
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.member == rhs.member
                && lhs.replaced == rhs.replaced
                && lhs.previousStatus == rhs.previousStatus
                && lhs.status == rhs.status
        }

        public func hash(into hasher: inout Hasher) {
            self.member.hash(into: &hasher)
        }

        /// Whether the resulting status is at least the supplied status.
        public func isAtLeast(_ status: Cluster.MemberStatus) -> Bool {
            self.status >= status
        }
    }
}
