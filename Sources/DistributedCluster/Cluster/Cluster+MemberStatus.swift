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
    /// Lifecycle status, ordered from joining through removal independently of reachability.
    public enum MemberStatus: String, CaseIterable, Codable, Comparable {
        /// Assumed dead; communication with this member must be refused even if it becomes responsive.
        case down = "down"
        /// Connected but awaiting the leader's decision before serving traffic.
        case joining = "joining"
        /// Gracefully leaving; hand-over may begin before the member is marked down.
        case leaving = "leaving"
        /// Reserved for future lifecycle states; callers must not exhaustively interpret this value.
        case nonExhaustive = "_PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE"
        /// Ready to serve traffic after the leader's decision.
        case operational = "up"
        /// Completely removed after downing and convergence; this value is not gossiped.
        case removed = "removed"

        /// Enumerates the supported lifecycle states in transition order, excluding the reserved sentinel.
        public static var allCases: [Self] {
            [.joining, .operational, .leaving, .down, .removed]
        }

        internal static let maxStrLen: Int = 7

        /// Orders members by lifecycle status.
        public static let lifecycleOrdering: (Cluster.Member, Cluster.Member) -> Bool = { lhs, rhs in
            lhs.status < rhs.status
        }

        /// Whether the status is joining.
        public var isJoining: Bool { self == .joining }

        /// Whether the member is operational.
        public var isUp: Bool { self == .operational }

        /// Whether the member is leaving.
        public var isLeaving: Bool { self == .leaving }

        /// Whether the member is down.
        public var isDown: Bool { self == .down }

        /// Whether the member has been removed.
        public var isRemoved: Bool { self == .removed }

        /// Compares states in the order joining, operational, leaving, down, removed.
        public static func < (lhs: Cluster.MemberStatus, rhs: Cluster.MemberStatus) -> Bool {
            switch lhs {
            case .joining:
                return rhs != .joining

            case .operational:
                return rhs == .leaving || rhs == .down || rhs == .removed

            case .leaving:
                return rhs == .down || rhs == .removed

            case .down:
                return rhs == .removed

            case .removed:
                return false

            case .nonExhaustive:
                fatalError("LHS is \(Self.self) [\(lhs)]. This should not happen, please file an issue.")
            }
        }

        /// Whether this status is at least the supplied lifecycle status.
        public func isAtLeast(_ status: Cluster.MemberStatus) -> Bool {
            self >= status
        }
    }
}
