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

import CoreMetrics
import DistributedActorsConcurrencyHelpers
import Logging
import NIO
import SWIM

extension ClusterShell {
    internal func onReachabilityChange(
        _ context: ActorContext<Message>,
        state previousState: ClusterShellState,
        change: Cluster.ReachabilityChange
    ) -> Behavior<Message> {
        var state: ClusterShellState = previousState
        guard state.membership.applyReachabilityChange(change) != nil else {
            return .same
        }

        // we want to update the snapshot before the events are published
        context.system.cluster.updateMembershipSnapshot(state.membership)

        // then publish events and update metrics
        self.publish(.reachabilityChange(change))
        self.recordMetrics(context.system.metrics, membership: state.membership)

        return self.ready(state: state)
    }

    /// Convenience function for directly handling down command in shell.
    /// Attempts to locate which member to down and delegates further.
    internal func onDownCommand(
        _ context: ActorContext<Message>, state previousState: ClusterShellState, member memberToDown: Cluster.Member
    ) -> ClusterShellState {
        var state: ClusterShellState = previousState

        guard let change = state.membership.applyMembershipChange(.init(member: memberToDown, toStatus: .down)) else {
            // The member was already replaced, or its down event was already sent.
            return state
        }

        // the change was applied, so we should update the membership and publish an event
        context.system.cluster.updateMembershipSnapshot(state.membership)
        self.publish(.membershipChange(change))
        self.tryConfirmDeadToSWIM(context, state, change: change)

        if let logChangeLevel = state.settings.logMembershipChanges {
            context.log.log(
                level: logChangeLevel,
                "Cluster membership change: \(reflecting: change)",
                metadata: [
                    "cluster/membership/change": "\(change)",
                    "cluster/membership": Logger.MetadataValue.array(
                        state.membership.members(atMost: .down).map { "\($0)" }
                    ),
                ]
            )
        }

        // Stop SWIM monitoring whenever a member is downed.
        self.activeSWIMActor.confirmDead(node: memberToDown.node)

        if memberToDown.node == state.selfNode {
            // ==== ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            // Down(self node); ensuring SWIM knows about this and should likely initiate graceful shutdown
            context.log.warning(
                "Self node was marked [.down]!",
                metadata: [
                    "cluster/membership": "\(state.membership)"
                ]
            )

            do {
                let onDownAction: (ClusterSystem) throws -> Void = context.system.settings.onDownAction.make()
                try onDownAction(context.system)
            } catch {
                context.system.log.error(
                    "Failed to executed onDownAction! Shutting down system forcefully!",
                    metadata: ["error": "\(error)"]
                )
                do {
                    try context.system.shutdown()
                } catch {
                    context.system.log.error("Failed shutting down actor system!", metadata: ["error": "\(error)"])
                }
            }

            state = self.interpretLeaderActions(context.system, state, state.collectLeaderActions())
            return state
        }
        // ==== ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Terminate association and Down the (other) node

        state = self.interpretLeaderActions(context.system, state, state.collectLeaderActions())
        self.terminateAssociation(context.system, state: &state, memberToDown.node)
        return state
    }
}
