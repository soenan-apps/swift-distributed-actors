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

import NIO

/// Initial protocol bytes: 0x5AC7 identifies SACT before handshake negotiation.
internal let kHandshakeMagicBytes: UInt16 = 0x5AC7

internal enum HandshakeStateMachine {
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Directives

    /// Directives are what instructs the state machine driver about what should be performed next.
    internal enum NegotiateDirective {
        /// The handshake has completed successfully, and shall be "upgraded" to an association.
        /// The handshake has fulfilled its purpose and may be dropped.
        case acceptAndAssociate(CompletedState)

        /// The handshake has failed for some reason and the connection should be immediately closed.
        case rejectHandshake(RejectedState)
    }

    /// Directives controlling attempting to schedule retries for shaking hands with remote node.
    internal enum RetryDirective {
        /// Abandons the handshake and clears the initiator's handshake state.
        case giveUpOnHandshake
        /// Retries after the supplied delay following a recoverable connection failure.
        case scheduleRetryHandshake(delay: Duration)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Handshake Initiated

    internal struct InitiatedState: Swift.CustomStringConvertible {
        internal let settings: ClusterSystemSettings

        internal var protocolVersion: ClusterSystem.Version {
            self.settings.protocolVersion
        }

        internal let remoteEndpoint: Cluster.Endpoint
        internal let localNode: Cluster.Node

        internal var handshakeReconnectBackoff: BackoffStrategy

        /// Channel which was established when we initiated the handshake (outgoing connection),
        /// which may want to be closed when we `abortHandshake` and want to terminate the related outgoing connection
        /// as we do so.
        ///
        /// This is ALWAYS set once the initial clientBootstrap has completed.
        internal var channel: Channel?

        internal var description: Swift.String {
            """
            InitiatedState(\
            remoteNode: \(self.remoteEndpoint), \
            localNode: \(self.localNode), \
            channel: \(optional: self.channel)\
            )
            """
        }

        internal init(
            settings: ClusterSystemSettings,
            localNode: Cluster.Node,
            connectTo remoteEndpoint: Cluster.Endpoint
        ) {
            precondition(
                localNode.endpoint != remoteEndpoint,
                "MUST NOT attempt connecting to own bind address. Address: \(remoteEndpoint)"
            )
            self.settings = settings
            self.localNode = localNode
            self.remoteEndpoint = remoteEndpoint
            // Each handshake owns its independently mutable reconnect backoff.
            self.handshakeReconnectBackoff = settings.handshakeReconnectBackoff
        }

        internal func makeOffer() -> Wire.HandshakeOffer {
            Wire.HandshakeOffer(
                version: self.protocolVersion,
                originNode: self.localNode,
                targetEndpoint: self.remoteEndpoint
            )
        }

        internal mutating func onConnectionEstablished(channel: Channel) {
            self.channel = channel
        }

        internal mutating func onHandshakeTimeout() -> RetryDirective {
            self.onConnectionError(
                HandshakeConnectionError(endpoint: self.remoteEndpoint, message: "Handshake timed out")
            )
        }

        internal mutating func onConnectionError(_: Error) -> RetryDirective {
            if let nextConnectionAttemptDelay = self.handshakeReconnectBackoff.next() {
                return .scheduleRetryHandshake(delay: nextConnectionAttemptDelay)
            }
            return .giveUpOnHandshake
        }
    }

    internal struct HandshakeConnectionError: Error, Equatable {
        internal let endpoint: Cluster.Endpoint
        internal let message: String
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Handshake In-Flight, and should attach to existing negotiation

    internal struct InFlightState {
        private let state: ReadOnlyClusterState

        internal init(state: ReadOnlyClusterState) {
            self.state = state
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Handshake Received

    /// Initial state for server side of handshake.
    internal struct HandshakeOfferReceivedState {
        private let state: ReadOnlyClusterState

        internal let offer: Wire.HandshakeOffer
        internal var boundAddress: Cluster.Node {
            self.state.selfNode
        }

        internal var protocolVersion: ClusterSystem.Version {
            self.state.settings.protocolVersion
        }

        internal init(state: ReadOnlyClusterState, offer: Wire.HandshakeOffer) {
            self.state = state
            self.offer = offer
        }

        internal func negotiate() -> HandshakeStateMachine.NegotiateDirective {
            guard self.boundAddress.endpoint == self.offer.targetEndpoint else {
                let error: HandshakeError = .targetHandshakeAddressMismatch(
                    self.offer,
                    selfNode: self.boundAddress
                )

                let rejectedState: RejectedState = RejectedState(
                    fromReceived: self,
                    remoteNode: self.offer.originNode,
                    error: error
                )
                //                self.whenCompleted.succeed(.reject(rejectedState.makeReject(whenHandshakeReplySent: {
                // () in
                //                    self.state.log.trace("Done rejecting handshake.")
                //                })))
                return .rejectHandshake(rejectedState)
            }

            // negotiate version
            if let rejectedState = self.negotiateVersion(local: self.protocolVersion, remote: self.offer.version) {
                //                self.whenCompleted.succeed(.reject(rejectedState.makeReject(whenHandshakeReplySent: {
                // () in
                //                    self.state.log.trace("Done rejecting handshake.")
                //                })))
                return .rejectHandshake(rejectedState)
            }

            // negotiate capabilities
            // self.negotiateCapabilities(...)

            let completed: CompletedState = CompletedState(fromReceived: self, remoteNode: offer.originNode)
            return .acceptAndAssociate(completed)
        }

        internal func negotiateVersion(local: ClusterSystem.Version, remote: ClusterSystem.Version) -> RejectedState? {
            guard local.major == remote.major else {
                let error: HandshakeError = HandshakeError.incompatibleProtocolVersion(
                    local: self.protocolVersion,
                    remote: self.offer.version
                )
                return RejectedState(fromReceived: self, remoteNode: self.offer.originNode, error: error)
            }

            return nil
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Handshake Completed

    /// State reached once we have received a `HandshakeAccepted` and are ready to create an association.
    /// This state is used to unlock creating a completed Association.
    internal struct CompletedState {
        internal let protocolVersion: ClusterSystem.Version
        internal var remoteNode: Cluster.Node
        internal var localNode: Cluster.Node
        //        let whenCompleted: EventLoopPromise<Wire.HandshakeResponse>
        // let unique association ID?

        // State Transition used by Client Side of initial Handshake.
        //
        // Since the client is the one who initiates the handshake, once it receives an Accept containing the remote
        // unique node
        // it may immediately transition to the completed state.
        internal init(fromInitiated initiated: InitiatedState, remoteNode: Cluster.Node) {
            precondition(
                initiated.localNode != remoteNode,
                "Node [\(initiated.localNode)] attempted to create association with itself."
            )
            self.protocolVersion = initiated.protocolVersion
            self.remoteNode = remoteNode
            self.localNode = initiated.localNode
            //            self.whenCompleted = initiated.whenCompleted
        }

        // State Transition used by Server Side on accepting a received Handshake.
        internal init(fromReceived received: HandshakeOfferReceivedState, remoteNode: Cluster.Node) {
            precondition(
                received.boundAddress != remoteNode,
                "Node [\(received.boundAddress)] attempted to create association with itself."
            )
            self.protocolVersion = received.protocolVersion
            self.remoteNode = remoteNode
            self.localNode = received.boundAddress
            //            self.whenCompleted = received.whenCompleted
        }

        internal func makeAccept(whenHandshakeReplySent: (() -> Void)?) -> Wire.HandshakeAccept {
            Wire.HandshakeAccept(
                version: self.protocolVersion,
                targetNode: self.localNode,
                originNode: self.remoteNode,
                whenHandshakeReplySent: whenHandshakeReplySent
            )
        }
    }

    internal struct RejectedState {
        internal let protocolVersion: ClusterSystem.Version
        internal let localNode: Cluster.Node
        internal let remoteNode: Cluster.Node
        internal let error: HandshakeError

        internal init(
            fromReceived state: HandshakeOfferReceivedState,
            remoteNode: Cluster.Node,
            error: HandshakeError
        ) {
            self.protocolVersion = state.protocolVersion
            self.localNode = state.boundAddress
            self.remoteNode = remoteNode
            self.error = error
        }

        internal func makeReject(whenHandshakeReplySent: @escaping () -> Void) -> Wire.HandshakeReject {
            Wire.HandshakeReject(
                version: self.protocolVersion,
                targetNode: self.localNode,
                originNode: self.remoteNode,
                reason: "\(self.error)",
                whenHandshakeReplySent: whenHandshakeReplySent
            )
        }
    }

    internal enum State {
        case completed(CompletedState)
        /// A handshake is already in-flight and was initiated by someone else previously.
        /// rather than creating another handshake dance, we will be notified along with the already initiated
        /// by someone else handshake completes.
        case inFlight(InFlightState)
        /// Stored the moment a handshake is initiated; may not yet have an underlying connection yet.
        case initiated(InitiatedState)
        case wasOfferedHandshake(HandshakeOfferReceivedState)
    }
}
