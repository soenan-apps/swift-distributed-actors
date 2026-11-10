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

import Logging

extension ClusterShell {
    internal func receiveShellCommand(
        _ context: ActorContext<Message>,
        state: ClusterShellState,
        command: CommandMessage
    ) -> Behavior<Message> {
        state.tracelog(
            .inbound,
            message: command,
            location: .init(file: #fileID, function: #function, line: #line)
        )

        switch command {
        case .handshakeWith(let node):
            return self.beginHandshake(context, state, with: node)

        case .handshakeWithSpecific(let node):
            return self.beginHandshake(context, state, with: node.endpoint)

        case .retryHandshake(let initiated):
            return self.retryHandshake(context, state, initiated: initiated)

        case let .failureDetectorReachabilityChanged(node, reachability):
            return self.receiveReachabilityChanged(context, state: state, node: node, reachability: reachability)

        case .shutdown(let receptacle):
            return self.onShutdownCommand(context, state: state, signalOnceUnbound: receptacle)

        case .downCommand(let endpoint):
            if let member = state.membership.anyMember(forEndpoint: endpoint) {
                return self.ready(state: self.onDownCommand(context, state: state, member: member))
            }
            return self.ready(state: state)

        case .downCommandMember(let member):
            return self.ready(state: self.onDownCommand(context, state: state, member: member))

        case .cleanUpAssociationTombstones:
            return self.cleanUpAssociationTombstones()
        }
    }

    private func receiveReachabilityChanged(
        _ context: ActorContext<Message>,
        state: ClusterShellState,
        node: Cluster.Node,
        reachability: Cluster.MemberReachability
    ) -> Behavior<Message> {
        guard let member = state.membership.member(node) else {
            return .same
        }
        switch reachability {
        case .reachable:
            return self.onReachabilityChange(
                context,
                state: state,
                change: .init(member: member.asReachable)
            )

        case .unreachable:
            return self.onReachabilityChange(
                context,
                state: state,
                change: .init(member: member.asUnreachable)
            )

        case .nonExhaustive:
            context.log.error(
                "Received Cluster.MemberReachability [\(reachability)]. This should not happen, please file an issue."
            )
            return .same
        }
    }

    internal func receiveQuery(
        _: ActorContext<Message>,
        state: ClusterShellState,
        query: QueryMessage
    ) -> Behavior<Message> {
        state.tracelog(
            .inbound,
            message: query,
            location: .init(file: #fileID, function: #function, line: #line)
        )

        switch query {
        case .associatedNodes(let replyTo):
            replyTo.tell(self.associatedNodes())
            return .same

        case .currentMembership(let replyTo):
            replyTo.tell(state.membership)
            return .same
        }
    }

    internal func receiveInbound(
        _ context: ActorContext<Message>,
        state: ClusterShellState,
        message: InboundMessage
    ) -> Behavior<Message> {
        switch message {
        case let .handshakeOffer(offer, channel, promise):
            self.tracelog(
                context,
                .receiveUnique(from: offer.originNode),
                message: offer,
                location: .init(file: #fileID, function: #function, line: #line)
            )
            return self.onHandshakeOffer(context, state, offer, inboundChannel: channel, replyInto: promise)

        case let .handshakeAccepted(accepted, channel):
            self.tracelog(
                context,
                .receiveUnique(from: accepted.targetNode),
                message: accepted,
                location: .init(file: #fileID, function: #function, line: #line)
            )
            return self.onHandshakeAccepted(context, state, accepted, channel: channel)

        case .handshakeRejected(let rejected):
            self.tracelog(
                context,
                .receiveUnique(from: rejected.targetNode),
                message: rejected,
                location: .init(file: #fileID, function: #function, line: #line)
            )
            return self.onHandshakeRejected(context, state, rejected)

        case let .handshakeFailed(fromNode, error):
            self.tracelog(
                context,
                .receive(from: fromNode),
                message: error,
                location: .init(file: #fileID, function: #function, line: #line)
            )
            return self.onHandshakeFailed(context, state, with: fromNode, error: error)

        case let .restInPeace(intendedNode, fromNode):
            self.tracelog(
                context,
                .receiveUnique(from: fromNode),
                message: message,
                location: .init(file: #fileID, function: #function, line: #line)
            )
            return self.onRestInPeace(context, state, intendedNode: intendedNode, fromNode: fromNode)
        }
    }

    /// Allows processing in one spot, all membership changes which we may have emitted in other places, due to joining,
    /// downing etc.
    internal func receiveChangeMembershipRequest(
        _ context: ActorContext<Message>,
        state previousState: ClusterShellState,
        event: Cluster.Event
    ) -> Behavior<Message> {
        var state: ClusterShellState = previousState
        self.tracelog(
            context,
            .receive(from: state.selfNode.endpoint),
            message: event,
            location: .init(file: #fileID, function: #function, line: #line)
        )

        // 1) IMPORTANT: We MUST apply and act on the incoming event FIRST, before handling the other events.
        // This is because:
        //   - is the event is a `leadershipChange` applying it could make us become the leader
        //   - if that happens, the 2) phase will collect leader actions (perhaps for the first time),
        //     and issue any pending up/down events.
        //   - For consistency such events MUST only be issued AFTER we have emitted the leadership change (!)
        //     Otherwise subscribers may end up seeing joining->up changes BEFORE they see the leadershipChange,
        //     which is not strictly wrong per se, however it is very confusing -- we know there MUST be a leader
        //     somewhere in order to perform those moves, so it is confusing if such joining->up events were to be
        //     seen by a subscriber before they saw "we have a leader".
        if state.applyClusterEvent(event).applied {
            state.latestGossip.incrementOwnerVersion()

            // Always FIRST update the snapshot, before emitting events:
            context.system.cluster.updateMembershipSnapshot(state.membership)

            // we only publish the event if it really caused a change in membership, to avoid echoing "the same" change
            // many times.
            self.publish(event)
        }  // else no "effective change", thus we do not publish events

        // 3) Collect and interpret leader actions which may result changing the membership and publishing events for
        // the changes
        let actions: [ClusterShellState.LeaderAction] = state.collectLeaderActions()
        state = self.interpretLeaderActions(context.system, state, actions)

        if case .membershipChange(let change) = event {
            self.tryConfirmDeadToSWIM(context, state, change: change)
            self.tryIntroduceGossipPeer(context, state, change: change)
        }

        return self.ready(state: state)
    }

    internal func receiveMembershipGossip(
        _ context: ActorContext<Message>,
        _ previousState: ClusterShellState,
        gossip: Cluster.MembershipGossip
    ) -> Behavior<Message> {
        self.tracelog(
            context,
            .gossip(gossip),
            message: gossip,
            location: .init(file: #fileID, function: #function, line: #line)
        )
        var state: ClusterShellState = previousState

        let beforeGossipMerge: Cluster.MembershipGossip = state.latestGossip

        let mergeDirective: Cluster.MembershipGossip.MergeDirective = state.latestGossip.mergeForward(incoming: gossip)
        self.logMembershipMerge(
            context.log,
            incoming: gossip,
            before: beforeGossipMerge,
            after: state.latestGossip,
            directive: mergeDirective
        )

        // we want to update the snapshot before the events are published
        context.system.cluster.updateMembershipSnapshot(state.membership)

        // Publish the events
        var eventsToPublish: [Cluster.Event] = []
        for effectiveChange in mergeDirective.effectiveChanges {
            // Publish a replacement's removal before the replacement member's change.
            if let replacementChange = effectiveChange.replacementDownPreviousNodeChange {
                eventsToPublish.append(.membershipChange(replacementChange))
                self.tryConfirmDeadToSWIM(context, state, change: replacementChange)
            }
            eventsToPublish.append(.membershipChange(effectiveChange))
            self.tryConfirmDeadToSWIM(context, state, change: effectiveChange)
        }

        Task { [eventsToPublish] in
            for event in eventsToPublish {
                await self.clusterEvents.publish(event)
            }
        }

        // follow up with leader actions
        let leaderActions: [ClusterShellState.LeaderAction] = state.collectLeaderActions()
        state = self.interpretLeaderActions(context.system, state, leaderActions)

        return self.ready(state: state)
    }

    private func logMembershipMerge(
        _ log: Logger,
        incoming: Cluster.MembershipGossip,
        before: Cluster.MembershipGossip,
        after: Cluster.MembershipGossip,
        directive: Cluster.MembershipGossip.MergeDirective
    ) {
        log.trace(
            """
            Local membership version is [.\(directive.causalRelation)] to incoming gossip; \
            Merge resulted in \(directive.effectiveChanges.count) changes.
            """,
            metadata: [
                "tag": "membership",
                "membership/changes": Logger.MetadataValue.array(
                    directive.effectiveChanges.map { change in
                        Logger.MetadataValue.stringConvertible(change)
                    }
                ),
                "gossip/incoming": .string("\(pretty: incoming)"),
                "gossip/before": .string("\(pretty: before)"),
                "gossip/now": .string("\(pretty: after)"),
            ]
        )
    }

}
