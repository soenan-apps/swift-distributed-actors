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
    /// Initiate a handshake to the `remoteNode`.
    /// Upon successful handshake, the `replyTo` actor shall be notified with its result, as well as the handshaked-with
    /// node shall be marked as `.joining`.
    ///
    /// Handshakes are currently not performed concurrently but one by one.
    internal func beginHandshake(
        _ context: ActorContext<Message>,
        _ previousState: ClusterShellState,
        with remoteNode: Cluster.Endpoint
    ) -> Behavior<Message> {
        var state: ClusterShellState = previousState

        guard remoteNode != state.selfNode.endpoint else {
            state.log.debug(
                """
                Ignoring attempt to handshake with myself; \
                Could have been issued as confused attempt to handshake as induced by discovery via gossip?
                """
            )
            return .same
        }

        // if an association exists for any Cluster.Node that this Node represents, we can use this and abort the
        // handshake dance here
        if let existingAssociation = self.getAnyExistingAssociation(with: remoteNode) {
            state.log.debug(
                """
                Association already allocated for remote: \(reflecting: remoteNode), \
                existing association: [\(existingAssociation)]
                """
            )
            switch existingAssociation.state {
            case .associating:
                // continue, we may be the first beginHandshake (as associations may be ensured outside of actor
                // context)
                ()

            case .associated:
                // nothing to do, we already associated
                return .same

            case .tombstone:
                return .same
            }
        }

        let handshakeState: HandshakeStateMachine.State = state.initHandshake(with: remoteNode)
        // we MUST register the intention of shaking hands with remoteAddress before obtaining the connection,
        // in order to let the fsm handle any retry decisions in face of connection failures et al.

        switch handshakeState {
        case .initiated(let initiated):
            state.log.debug(
                "Initiated handshake: \(initiated)",
                metadata: [
                    "cluster/associatedNodes": "\(self.associatedNodes())"
                ]
            )
            return self.connectSendHandshakeOffer(context, state, initiated: initiated)

        case .wasOfferedHandshake, .inFlight, .completed:
            state.log.debug("Handshake in other state: \(handshakeState)")
            // the reply will be handled already by the future.whenComplete we've set up above here
            // so nothing to do here, just become the next state
            return self.ready(state: state)
        }
    }

    internal func retryHandshake(
        _ context: ActorContext<Message>,
        _ state: ClusterShellState,
        initiated: HandshakeStateMachine.InitiatedState
    ) -> Behavior<Message> {
        state.log.debug("Retry handshake with: \(initiated.remoteEndpoint)")
        //
        //
        //        let assoc = self.getRetryAssociation(with: initiated.remoteNode)

        return self.connectSendHandshakeOffer(context, state, initiated: initiated)
    }

    internal func connectSendHandshakeOffer(
        _ context: ActorContext<Message>,
        _ previousState: ClusterShellState,
        initiated: HandshakeStateMachine.InitiatedState
    ) -> Behavior<Message> {
        var state: ClusterShellState = previousState
        state.log.debug(
            "Extending handshake offer",
            metadata: [
                "handshake/remoteNode": "\(initiated.remoteEndpoint)"
            ]
        )

        let offer: Wire.HandshakeOffer = initiated.makeOffer()
        self.tracelog(
            context,
            .send(endpoint: initiated.remoteEndpoint),
            message: offer,
            location: .init(file: #fileID, function: #function, line: #line)
        )

        let outboundChanElf: EventLoopFuture<Channel> = self.bootstrapClientSide(
            system: context.system,
            shell: context.myself,
            handshake: .init(endpoint: initiated.remoteEndpoint, offer: offer),
            settings: state.settings,
            serializationPool: self.serializationPool
        )

        // the timeout is being handled by the `connectTimeout` socket option in NIO, so it is safe to use an infinite
        // timeout here
        return context.awaitResult(of: outboundChanElf, timeout: .effectivelyInfinite) { result in
            switch result {
            case .success(let chan):
                return self.ready(state: state.onHandshakeChannelConnected(initiated: initiated, channel: chan))

            case .failure(let error):
                return self.onOutboundConnectionError(context, state, with: initiated.remoteEndpoint, error: error)
            }
        }
    }
}
