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

import DistributedActorsConcurrencyHelpers
import Logging
import NIO

extension ClusterShellState {

    internal struct AppliedClusterEventDirective {
        // True if the change was applied, modifying the Membership.
        internal let applied: Bool
    }
    /// Generates and applies changes; generating actions to be taken by the `ClusterShell` if and only if it is the
    /// Leader,
    /// after this change has been applied.
    internal mutating func applyClusterEvent(_ event: Cluster.Event) -> AppliedClusterEventDirective {
        var changeWasApplied: Bool

        switch event {
        case .leadershipChange(let change):
            do {
                if let appliedChange = try self.membership.applyLeadershipChange(to: change.newLeader) {
                    self.log.debug("Leader change: \(appliedChange)", metadata: self.metadata)
                    changeWasApplied = true
                } else {
                    changeWasApplied = false
                }
            } catch {
                self.log.warning(
                    "Unable to apply leadership change: \(change), error: \(error)", metadata: self.metadata
                )
                changeWasApplied = false
            }

        case .membershipChange(let change):
            if let appliedChange = self.membership.applyMembershipChange(change) {
                self.log.trace("Applied change via cluster event: \(appliedChange)", metadata: self.metadata)
                changeWasApplied = true
            } else {
                changeWasApplied = false
            }

        case .reachabilityChange(let change):
            if self.membership.applyReachabilityChange(change) != nil {
                self.log.trace("Applied reachability change: \(change)", metadata: self.metadata)
                changeWasApplied = true
            } else {
                changeWasApplied = false
            }

        case .snapshot(let snapshot):
            // Realistically we are a SOURCE of snapshots, not a destination of them, however for completeness let's
            // implement it:
            changeWasApplied = false
            for change in Cluster.Membership.difference(from: .empty, to: snapshot).changes {
                let directive: AppliedClusterEventDirective = self.applyClusterEvent(.membershipChange(change))
                changeWasApplied = changeWasApplied || directive.applied
                // actions we'll calculate below, once
            }

        case .nonExhaustive:
            self.log.error("Received Cluster.Event [\(event)]. This should not happen, please file an issue.")
            changeWasApplied = false
        }

        guard changeWasApplied else {
            return .init(applied: changeWasApplied)
        }

        self.log.trace("Membership updated on [\(self.selfNode)] by \(event): \(pretty: self.membership)")
        return .init(applied: changeWasApplied)
    }
}
