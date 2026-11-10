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
    /// Applies any kind of ``Cluster/Event`` to the `Membership`, modifying it appropriately.
    /// This apply does not yield detailed information back about the type of change performed,
    /// and is useful as a catch-all to keep a `Membership` copy up-to-date, but without reacting on any specific
    /// transition.
    ///
    /// - SeeAlso: `apply(_:)`, `applyLeadershipChange(to:)`, `applyReachabilityChange(_:)` to receive specific diffs
    /// reporting about the effect
    /// a change had on the membership.
    public mutating func apply(event: Cluster.Event) throws {
        switch event {
        case .snapshot(let snapshot):
            self = snapshot

        case .membershipChange(let change):
            _ = self.applyMembershipChange(change)

        case .leadershipChange(let change):
            _ = try self.applyLeadershipChange(to: change.newLeader)

        case .reachabilityChange(let change):
            _ = self.applyReachabilityChange(change)

        case .nonExhaustive:
            ()  // do nothing
        }
    }
}
