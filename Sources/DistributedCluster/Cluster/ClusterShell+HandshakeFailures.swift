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
    internal func onOutboundConnectionError(
        _ context: ActorContext<Message>,
        _ previousState: ClusterShellState,
        with remoteNode: Cluster.Endpoint,
        error: Error
    ) -> Behavior<Message> {
        var state: ClusterShellState = previousState
        state.log.debug(
            "Failed to establish outbound channel to \(remoteNode), error: \(error)",
            metadata: ["handshake/remoteNode": "\(remoteNode)", "handshake/error": "\(error)"]
        )
        guard let handshakeState = state.handshakeInProgress(with: remoteNode) else {
            state.log.warning(
                "Connection error for handshake which is not in progress, this should not happen, but is harmless.",
                metadata: ["handshake/remoteNode": "\(remoteNode)", "handshake/error": "\(error)"]
            )
            return .same
        }
        switch handshakeState {
        case .initiated(var initiated):
            self.handleInitiatedConnectionError(context, state: &state, initiated: &initiated, error: error)

        case .wasOfferedHandshake(let offered):
            preconditionFailure(
                """
                Outbound connection error should never happen on receiving end. \
                State was: [\(offered)], error was: \(error)
                """
            )

        case .completed(let completed):
            state.log.notice(
                """
                Stored handshake state is .completed, while outbound connection establishment failed. \
                Assuming existing completed association is correct.
                """,
                metadata: [
                    "handshake/error": "\(error)", "handshake/state": "\(state)",
                    "handshake/completed": "\(completed)",
                ]
            )

        case .inFlight:
            preconditionFailure(
                """
                An in-flight marker state should never be stored, yet was encountered in \(#function). \
                State was: [\(state)], error was: \(error)
                """
            )
        }
        return self.ready(state: state)
    }

    private func handleInitiatedConnectionError(
        _ context: ActorContext<Message>,
        state: inout ClusterShellState,
        initiated: inout HandshakeStateMachine.InitiatedState,
        error: Error
    ) {
        guard initiated.channel == nil else {
            fatalError("Seems we DO have a channel already! \(initiated)\n \(state)")
        }
        let remoteNode: Cluster.Endpoint = initiated.remoteEndpoint
        switch initiated.onConnectionError(error) {
        case .scheduleRetryHandshake(let retryDelay):
            state.log.debug(
                "Schedule handshake retry",
                metadata: [
                    "handshake/remoteNote": "\(remoteNode)",
                    "handshake/retryDelay": "\(retryDelay)",
                ]
            )
            context.timers.startSingle(
                key: TimerKey("handshake-timer-\(remoteNode)"),
                message: .command(.retryHandshake(initiated)),
                delay: retryDelay
            )
            // Persist the updated retry backoff.
            state.handshakesByEndpoint[remoteNode] = .initiated(initiated)

        case .giveUpOnHandshake:
            if let handshake = state.closeOutboundHandshakeChannel(with: remoteNode) {
                state.log.warning(
                    "Giving up on handshake with node [\(remoteNode)]",
                    metadata: ["handshake/error": "\(error)", "handshake/state": "\(handshake)"]
                )
            }
        }
    }
}
