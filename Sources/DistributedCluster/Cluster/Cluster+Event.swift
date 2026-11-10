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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Cluster Events

extension Cluster {
    /// Represents cluster events, most notably regarding membership and reachability of other members of the cluster.
    ///
    /// Inspect directly, or apply to a `Membership` copy to react to cluster membership state.
    public enum Event: Codable, Equatable {
        case snapshot(Membership)
        case membershipChange(MembershipChange)
        case reachabilityChange(ReachabilityChange)
        case leadershipChange(LeadershipChange)
        case nonExhaustive
    }
}
