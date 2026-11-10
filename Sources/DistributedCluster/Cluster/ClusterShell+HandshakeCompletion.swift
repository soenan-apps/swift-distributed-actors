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
    internal func onHandshakeAccepted(
        _ context: ActorContext<Message>,
        _ previousState: ClusterShellState,
        _ inboundAccept: Wire.HandshakeAccept,
        channel: Channel
    ) -> Behavior<Message> {
        var state: ClusterShellState = previousState

        state.log.debug(
            "Accept association with \(reflecting: inboundAccept.targetNode)!",
            metadata: [
                "handshake/localNode": "\(inboundAccept.originNode)",
                "handshake/remoteNode": "\(inboundAccept.targetNode)",
                "handshake/channel": "\(channel)",
            ]
        )

        guard let handshakeCompleted = state.incomingHandshakeAccept(inboundAccept) else {
            if self.associatedNodes().contains(inboundAccept.targetNode) {
                // this seems to be a re-delivered accept, we already accepted association with this node.
                return .same
            }
            state.log.error(
                """
                Unexpected handshake accept received: [\(inboundAccept)]. \
                No handshake was in progress with \(inboundAccept.targetNode)
                """
            )
            return .same
        }

        // 1) Complete the handshake (in the cluster state)
        let directive: ClusterShellState.AssociatedDirective = state.completeHandshakeAssociate(
            self,
            handshakeCompleted,
            channel: channel
        )

        // 1.1) This association may mean that we've "replaced" a previously known node of the same host:port,
        //   In case of such replacement we must down and terminate the association of the previous node.
        //
        //   This MUST be called before we complete the new association as it may need to terminate the old one.
        // Publish a replaced member's down event before announcing the replacement's join.
        self.handlePotentialAssociatedMemberReplacement(
            directive: directive,
            accept: inboundAccept,
            context: context,
            state: &state
        )
        self.completeNegotiatedAssociation(directive, state: state)

        // we want to update the snapshot before the events are published
        context.system.cluster.updateMembershipSnapshot(state.membership)

        // 3) publish any cluster events this association caused.
        //    As the new association is stored, any reactions to these events will use the right underlying connection
        if let change = directive.membershipChange {
            self.publish(.membershipChange(change), to: state.events)
            self.tryConfirmDeadToSWIM(context, state, change: change)
            self.tryIntroduceGossipPeer(context, state, change: change)
        }

        // Apply leader actions before recording the resulting membership metrics.
        let actions: [ClusterShellState.LeaderAction] = state.collectLeaderActions()
        state = self.interpretLeaderActions(context.system, state, actions)

        self.recordMetrics(context.system.metrics, membership: state.membership)

        return self.ready(state: state)
    }

    /// An accept may imply that it replaced a previously associated member.
    /// If so, this method will .down it in the membership and terminate the previous instances association.
    internal func handlePotentialAssociatedMemberReplacement(
        directive: ClusterShellState.AssociatedDirective,
        accept _: Wire.HandshakeAccept,
        context: ActorContext<Message>,
        state: inout ClusterShellState
    ) {
        if let replacedMember = directive.membershipChange?.replaced {
            // the change was a replacement and thus we need to down the old member (same host:port as the new one),
            // and terminate its association.

            state.log.info(
                """
                Accepted handshake from [\(reflecting: directive.handshake.remoteNode)] \
                which replaces the previously known: [\(reflecting: replacedMember)].
                """
            )

            // We MUST be careful to first terminate the association and then store the new one in 2)
            self.terminateAssociation(context.system, state: &state, replacedMember.node)

            // we want to update the snapshot before the events are published
            context.system.cluster.updateMembershipSnapshot(state.membership)

            // By emitting these `change`s, we not only let anyone interested know about this,
            // but we also enable the shell (or leadership) to update the leader if it needs changing.
            //
            // We MUST emit this `.down` before emitting the replacement's event
            let change: Cluster.MembershipChange = Cluster.MembershipChange(member: replacedMember, toStatus: .down)
            self.publish(.membershipChange(change), to: state.events)
            self.tryConfirmDeadToSWIM(context, state, change: change)
        }
    }

    internal func onHandshakeRejected(
        _ context: ActorContext<Message>,
        _ previousState: ClusterShellState,
        _ reject: Wire.HandshakeReject
    ) -> Behavior<Message> {
        var state: ClusterShellState = previousState

        // A concurrent connection may have completed after this connection was closed by the tie-break.
        if let existingAssociation = self.getSpecificExistingAssociation(with: reject.targetNode),
            existingAssociation.isAssociating {
            state.log.warning(
                "Handshake rejected by [\(reject.targetNode)], it was associating and is now tombstoned",
                metadata: state.metadataForHandshakes(node: reject.targetNode, error: nil)
            )
            self.terminateAssociation(context.system, state: &state, reject.targetNode)
            return self.ready(state: state)
        }

        if let existingAssociation = self.getAnyExistingAssociation(with: reject.targetNode.endpoint),
            existingAssociation.isAssociated || existingAssociation.isTombstone {
            state.log.debug(
                """
                Handshake rejected by [\(reject.targetNode)], however existing association with node exists. \
                Could be that a concurrent handshake was failed on purpose.
                """,
                metadata: state.metadataForHandshakes(node: reject.targetNode, error: nil)
            )
            return .same
        }

        state.log.warning(
            "Handshake rejected by [\(reject.targetNode)], reason: \(reject.reason)",
            metadata: state.metadataForHandshakes(node: reject.targetNode, error: nil)
        )

        return .same
    }

    internal func onHandshakeFailed(
        _: ActorContext<Message>,
        _ state: ClusterShellState,
        with endpoint: Cluster.Endpoint,
        error: Error
    ) -> Behavior<Message> {
        // A concurrent connection may have completed after this connection was closed by the tie-break.
        if let existingAssociation = self.getAnyExistingAssociation(with: endpoint),
            existingAssociation.isAssociated || existingAssociation.isTombstone {
            state.log.debug(
                """
                Handshake failed, however existing association with node exists. \
                Could be that a concurrent handshake was failed on purpose.
                """,
                metadata: state.metadataForHandshakes(node: nil, error: error)
            )
            return .same
        }

        guard state.handshakeInProgress(with: endpoint) != nil else {
            state.log.debug(
                """
                Received handshake failed notification, however handshake is not in progress, \
                error: \(message: error)
                """,
                metadata: [
                    "handshake/node": "\(endpoint)"
                ]
            )
            return .same
        }

        state.log.warning(
            "Handshake error while connecting [\(endpoint)]: \(error)",
            metadata: state.metadataForHandshakes(node: nil, error: error)
        )

        return .same
    }

    internal func onRestInPeace(
        _ context: ActorContext<Message>,
        _ state: ClusterShellState,
        intendedNode _: Cluster.Node,
        fromNode: Cluster.Node
    ) -> Behavior<Message> {
        let myselfNode: Cluster.Node = state.selfNode

        guard !context.system.isShuttingDown else {
            // we are already shutting down thus other nodes declaring us as down is expected
            state.log.trace(
                """
                Already shutting down, received .restInPeace from [\(fromNode)], this is expected, \
                other nodes may sever their connections with this node while we terminate.
                """,
                metadata: [
                    "sender/node": "\(String(reflecting: fromNode))"
                ]
            )
            return .same
        }

        state.log.warning(
            """
            Received .restInPeace from \(fromNode), meaning this node is known to be .down or worse, \
            and should terminate. Initiating self .down-ing.
            """,
            metadata: [
                "sender/node": "\(String(reflecting: fromNode))"
            ]
        )

        guard let myselfMember = state.membership.member(myselfNode) else {
            state.log.error(
                """
                Unable to find Cluster.Member for \(myselfNode) self node! \
                This should not happen, please file an issue.
                """
            )
            return .same
        }

        return self.ready(state: self.onDownCommand(context, state: state, member: myselfMember))
    }

}
