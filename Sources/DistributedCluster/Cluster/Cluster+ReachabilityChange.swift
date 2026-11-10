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
    /// Emitted when the reachability of a member changes, as determined by a failure detector (e.g. `SWIM`).
    public struct ReachabilityChange: Equatable {
        public let member: Cluster.Member

        /// - SeeAlso: `MemberReachability`
        public var reachability: MemberReachability {
            self.member.reachability
        }

        /// This change is to a `.reachable` state of the `Member`
        public var toReachable: Bool {
            self.member.reachability == .reachable
        }

        /// This change is to a `.unreachable` state of the `Member`
        public var toUnreachable: Bool {
            self.member.reachability == .unreachable
        }

        public init(member: Member) {
            self.member = member
        }
    }
}
