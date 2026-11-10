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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Collect leader actions

extension ClusterShellState {
    internal enum LeaderAction: Equatable {
        case moveMember(Cluster.MembershipChange)
        case removeMember(alreadyDownMember: Cluster.Member)
    }

    /// If, and only if, the current node is a leader it performs a set of tasks, such as moving nodes to `.operational`
    /// etc.
    internal func collectLeaderActions() -> [LeaderAction] {
        guard self.membership.isLeader(self.selfNode) else {
            return []  // since we are not the leader, we perform no tasks
        }

        guard self.latestGossip.converged() else {
            return []  // leader actions are only performed when up nodes are converged
        }

        func collectMemberUpMoves() -> [LeaderAction] {
            let joiningMembers: [Cluster.Member] =
                self.membership.members(withStatus: .joining).sorted(by: Cluster.Member.ageOrdering)

            return joiningMembers.map { joiningMember in
                let change: Cluster.MembershipChange = .init(member: joiningMember, toStatus: .operational)
                return LeaderAction.moveMember(change)
            }
        }

        func collectDownMemberRemovals() -> [LeaderAction] {
            let toExitMembers: [Cluster.Member] = self.membership.members(withStatus: .down)

            return toExitMembers.map { member in
                LeaderAction.removeMember(alreadyDownMember: member)
            }
        }

        var leadershipActions: [LeaderAction] = []
        leadershipActions += collectMemberUpMoves()
        leadershipActions += collectDownMemberRemovals()

        return leadershipActions
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Interpret leader actions in Shell

extension ClusterShell {
    internal func interpretLeaderActions(
        _ system: ClusterSystem,
        _ previousState: ClusterShellState,
        _ leaderActions: [ClusterShellState.LeaderAction]
    ) -> ClusterShellState {
        guard !leaderActions.isEmpty else {
            return previousState
        }

        var state: ClusterShellState = previousState
        state.log.trace(
            "Performing leader actions: \(leaderActions)",
            metadata: [
                "tag": "leader-action",
                "leader/actions": "\(leaderActions)",
                "gossip/converged": "\(state.latestGossip.converged())",
                "gossip/current": "\(state.latestGossip)",
            ]
        )

        // This "dance" about collecting events first and only then emitting them is important for ordering guarantees
        // with regards to the membership snapshot. We always want the snapshot to be in sync when an actor receives an
        // update.
        // The snapshot therefore MUST be updated BEFORE we emit events.
        var eventsToPublish: [Cluster.Event] = []
        for leaderAction in leaderActions {
            switch leaderAction {
            case .moveMember(let movingUp):
                eventsToPublish += self.interpretMoveMemberLeaderAction(&state, movingUp: movingUp)

            case .removeMember(let memberToRemove):
                eventsToPublish += self.interpretRemoveMemberLeaderAction(
                    system, &state, memberToRemove: memberToRemove
                )
            }
        }

        system.cluster.updateMembershipSnapshot(state.membership)

        Task { [eventsToPublish, state] in
            for event in eventsToPublish {
                await state.events.publish(event)
            }
        }

        previousState.log.trace(
            "Membership state after leader actions: \(state.membership)",
            metadata: [
                "tag": "leader-action",
                "gossip/current": "\(state.latestGossip)",
                "gossip/before": "\(previousState.latestGossip)",
            ]
        )

        return state
    }

    internal func interpretMoveMemberLeaderAction(
        _ state: inout ClusterShellState, movingUp: Cluster.MembershipChange
    ) -> [Cluster.Event] {
        var events: [Cluster.Event] = []
        guard let change = state.membership.applyMembershipChange(movingUp) else {
            return []
        }

        if let downReplacedNodeChange = change.replacementDownPreviousNodeChange {
            state.log.debug("Downing replaced member: \(change)", metadata: ["tag": "leader-action"])
            events.append(.membershipChange(downReplacedNodeChange))
        }

        state.log.debug("Leader moved member: \(change)", metadata: ["tag": "leader-action"])
        events.append(.membershipChange(change))

        return events
    }

    /// Removal also terminates (and tombstones) the association to the given node.
    internal func interpretRemoveMemberLeaderAction(
        _ system: ClusterSystem, _ state: inout ClusterShellState, memberToRemove: Cluster.Member
    ) -> [Cluster.Event] {
        let previousGossip: Cluster.MembershipGossip = state.latestGossip
        // !!! IMPORTANT !!!
        // Prune underlying gossip; the wrapper enforces forward-only vector time.
        guard let removalChange = state.latestGossipStorage.pruneMember(memberToRemove) else {
            return []
        }
        state.latestGossipStorage.incrementOwnerVersion()
        state.gossiperControl.update(payload: state.latestGossipStorage)

        self.terminateAssociation(system, state: &state, memberToRemove.node)

        state.log.info(
            "Leader removed member: \(memberToRemove), all nodes are certain to have seen it as [.down] before",
            metadata: { () -> Logger.Metadata in
                var metadata: Logger.Metadata = [
                    "tag": "leader-action"
                ]
                if state.log.logLevel == .trace {
                    metadata["gossip/current"] = "\(state.latestGossip)"
                    metadata["gossip/before"] = "\(previousGossip)"
                }
                return metadata
            }()
        )

        // or do we need to push a round of gossip with .removed anyway?
        return [.membershipChange(removalChange)]
    }
}
