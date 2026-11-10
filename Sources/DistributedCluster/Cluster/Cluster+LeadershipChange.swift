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
    /// Emitted when a change in leader is decided.
    public struct LeadershipChange: Hashable {
        // let role: Role if this leader was of a specific role, carry the info here? same for DC?
        public let oldLeader: Cluster.Member?
        public let newLeader: Cluster.Member?

        #if DEBUG
        internal let file: String
        internal let line: UInt
        #endif

        #if DEBUG
        public init?(
            oldLeader: Cluster.Member?,
            newLeader: Cluster.Member?,
            file: String = #filePath,
            line: UInt = #line
        ) {
            guard oldLeader != newLeader else {
                return nil
            }
            self.oldLeader = oldLeader
            self.newLeader = newLeader

            self.file = file
            self.line = line
        }

        #else
        /// A change is only returned when `oldLeader` and `newLeader` are different.
        /// In order to avoid issuing changes which would be no-ops, the initializer fails if they are equal.
        public init?(oldLeader: Cluster.Member?, newLeader: Cluster.Member?) {
            guard oldLeader != newLeader else {
                return nil
            }
            self.oldLeader = oldLeader
            self.newLeader = newLeader
        }
        #endif

        public static func == (lhs: Self, rhs: Self) -> Bool {
            if lhs.oldLeader != rhs.oldLeader {
                return false
            }
            if lhs.newLeader != rhs.newLeader {
                return false
            }
            return true
        }
        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.oldLeader)
            hasher.combine(self.newLeader)
        }
    }
}
