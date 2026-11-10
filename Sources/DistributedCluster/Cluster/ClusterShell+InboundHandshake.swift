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
    internal func rejectIfNodeAlreadyLeaving(
        _: ActorContext<Message>,
        _ state: ClusterShellState,
        _ offer: Wire.HandshakeOffer
    ) -> Wire.HandshakeReject? {
        let member: Cluster.Member = state.selfMember

        if member.status.isAtLeast(.leaving) {
            state.log.notice("Received handshake while already [\(member.status)]")

            return .init(
                version: state.settings.protocolVersion,
                targetNode: state.selfNode,
                originNode: offer.originNode,
                reason: "Node already leaving cluster.",
                whenHandshakeReplySent: nil
            )
        }

        // let's try that to make that handshake
        return nil
    }

    /// Initial entry point for accepting a new connection; Potentially allocates new handshake state machine.
    /// - parameter inboundChannel: the inbound connection channel that the other node has opened and is offering its
    /// handshake on,
    ///   (as opposed to the channel which we may have opened when we first extended a handshake to that node which
    /// would be stored in `state`)
    internal func onHandshakeOffer(
        _ context: ActorContext<Message>,
        _ previousState: ClusterShellState,
        _ offer: Wire.HandshakeOffer,
        inboundChannel: Channel,
        replyInto handshakePromise: EventLoopPromise<Wire.HandshakeResponse>
    ) -> Behavior<Message> {
        var state: ClusterShellState = previousState
        if let rejection = self.rejectIfNodeAlreadyLeaving(context, state, offer) {
            handshakePromise.succeed(.reject(rejection))
            return .same
        }
        let association: Association? = self.getSpecificExistingAssociation(with: offer.originNode)
        switch state.onIncomingHandshakeOffer(
            offer: offer,
            existingAssociation: association,
            incomingChannel: inboundChannel
        ) {
        case .negotiateIncoming(let handshake):
            // Reserve the association before negotiation can trigger another outbound handshake.
            _ = self.getEnsureAssociation(with: offer.originNode)
            switch handshake.negotiate() {
            case .acceptAndAssociate(let completed):
                return self.acceptIncomingHandshake(
                    context,
                    state: &state,
                    handshake: completed,
                    channel: inboundChannel,
                    replyTo: handshakePromise
                )

            case .rejectHandshake(let rejected):
                state.log.warning(
                    """
                    Rejecting handshake from \(offer.originNode), \
                    error: [\(rejected.error)]:\(type(of: rejected.error))
                    """
                )
                // The channel stays open until the rejection has been sent.
                let reject: Wire.HandshakeReject = rejected.makeReject {
                    self.terminateAssociation(context.system, state: &state, rejected.remoteNode)
                }
                self.tracelog(
                    context,
                    .send(endpoint: offer.originNode.endpoint),
                    message: reject,
                    location: .init(file: #fileID, function: #function, line: #line)
                )
                handshakePromise.succeed(.reject(reject))
                return self.ready(state: state)
            }

        case .abortIncomingHandshake(let error):
            state.log.debug("Aborting incoming handshake: \(error)")
            handshakePromise.fail(error)
            state.closeHandshakeChannel(offer: offer, channel: inboundChannel)
            return .same
        }
    }

    private func acceptIncomingHandshake(
        _ context: ActorContext<Message>,
        state: inout ClusterShellState,
        handshake: HandshakeStateMachine.CompletedState,
        channel: Channel,
        replyTo promise: EventLoopPromise<Wire.HandshakeResponse>
    ) -> Behavior<Message> {
        state.log.trace(
            "Accept handshake with \(reflecting: handshake.remoteNode)!",
            metadata: ["handshake/channel": "\(channel)"]
        )
        let accept: Wire.HandshakeAccept = handshake.makeAccept(whenHandshakeReplySent: nil)
        self.tracelog(
            context,
            .send(endpoint: handshake.remoteNode.endpoint),
            message: accept,
            location: .init(file: #fileID, function: #function, line: #line)
        )
        promise.succeed(.accept(accept))
        let directive: ClusterShellState.AssociatedDirective =
            state.completeHandshakeAssociate(self, handshake, channel: channel)
        // Terminate a replaced member before storing its replacement's association.
        self.handlePotentialAssociatedMemberReplacement(
            directive: directive,
            accept: accept,
            context: context,
            state: &state
        )
        self.completeNegotiatedAssociation(directive, state: state)
        // Store the association and snapshot before subscribers can react to the membership event.
        if let change = directive.membershipChange {
            context.system.cluster.updateMembershipSnapshot(state.membership)
            self.publish(.membershipChange(change), to: state.events)
            self.tryIntroduceGossipPeer(context, state, change: change)
        }
        let actions: [ClusterShellState.LeaderAction] = state.collectLeaderActions()
        state = self.interpretLeaderActions(context.system, state, actions)
        self.recordMetrics(context.system.metrics, membership: state.membership)
        return self.ready(state: state)
    }

    internal func completeNegotiatedAssociation(
        _ directive: ClusterShellState.AssociatedDirective,
        state: ClusterShellState
    ) {
        do {
            try self.completeAssociation(directive)
            state.log.trace(
                "Associated with: \(reflecting: directive.handshake.remoteNode)",
                metadata: [
                    "membership/change": .string("\(optional: directive.membershipChange)"),
                    "membership": "\(state.membership)",
                ]
            )
        } catch {
            state.log.warning(
                """
                Error while trying to complete association with: \
                \(reflecting: directive.handshake.remoteNode), error: \(error)
                """,
                metadata: [
                    "membership/change": .string("\(optional: directive.membershipChange)"),
                    "membership": "\(state.membership)",
                    "association/error": "\(error)",
                ]
            )
        }
    }
}
