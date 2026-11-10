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
    /// Failure-detector assessment, which may change repeatedly independently of lifecycle status.
    public enum MemberReachability: String, Codable, Equatable {
        /// Reserved for future reachability states.
        case nonExhaustive = "_PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE"
        /// Responding to failure-detector probes.
        case reachable = "reachable"
        /// Not responding to probes and potentially eligible for downing.
        case unreachable = "unreachable"

        /// Whether the member is responding to probes.
        public var isReachable: Bool { self == .reachable }

        /// Whether the failure detector considers the member unreachable.
        public var isUnreachable: Bool { self == .unreachable }
    }
}
