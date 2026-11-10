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

    internal enum OnIncomingHandshakeOfferDirective {
        case negotiateIncoming(HandshakeStateMachine.HandshakeOfferReceivedState)
        /// An existing handshake with given peer is already in progress,
        /// do not negotiate but rest assured that the association will be handled properly by the already ongoing
        /// process.
        case abortIncomingHandshake(HandshakeStateMachine.HandshakeConnectionError)
    }

    internal struct AssociatedDirective {
        internal let membershipChange: Cluster.MembershipChange?
        //        let membershipChange: Cluster.MembershipChange
        internal let handshake: HandshakeStateMachine.CompletedState
        internal let channel: Channel
    }
    /// This is the entry point for a client initiating a handshake with a remote node.
    ///
    /// This MAY return `inFlight`, in which case it means someone already initiated a handshake with given node,
    /// and we should _do nothing_ and trust that our `whenCompleted` will be notified when the already in-flight
    /// handshake completes.
    internal mutating func initHandshake(with remoteNode: Cluster.Endpoint) -> HandshakeStateMachine.State {
        if let handshakeState = self.handshakeInProgress(with: remoteNode) {
            switch handshakeState {
            case .initiated:
                return .inFlight(HandshakeStateMachine.InFlightState(state: self))

            case .completed:
                return .inFlight(HandshakeStateMachine.InFlightState(state: self))

            case .wasOfferedHandshake:
                return .inFlight(HandshakeStateMachine.InFlightState(state: self))

            case .inFlight:
                fatalError(
                    """
                    An inFlight may never be stored, yet seemingly was! \
                    Offending state: \(self) for node \(remoteNode)
                    """
                )
            }
        }

        let initiated: HandshakeStateMachine.InitiatedState = HandshakeStateMachine.InitiatedState(
            settings: self.settings,
            localNode: self.selfNode,
            connectTo: remoteNode
        )
        let handshakeState: HandshakeStateMachine.State = HandshakeStateMachine.State.initiated(initiated)
        self.handshakesByEndpoint[remoteNode] = handshakeState
        return handshakeState
    }

    internal mutating func onHandshakeChannelConnected(
        initiated previousHandshake: HandshakeStateMachine.InitiatedState, channel: Channel
    ) -> ClusterShellState {
        #if DEBUG
        let handshakeInProgress: HandshakeStateMachine.State? =
            self.handshakeInProgress(with: previousHandshake.remoteEndpoint)

        if case .some(.initiated(let existingInitiated)) = handshakeInProgress {
            if existingInitiated.remoteEndpoint != previousHandshake.remoteEndpoint {
                fatalError(
                    """
                    onHandshakeChannelConnected MUST be called with the existing ongoing previousHandshake \
                    handshake! Existing: \(existingInitiated), passed in: \(previousHandshake).
                    """
                )
            }
            if existingInitiated.channel != nil {
                fatalError(
                    """
                    onHandshakeChannelConnected should only be invoked once on an initiated state; \
                    yet seems the state already has a channel! Was: \(String(reflecting: handshakeInProgress))
                    """
                )
            }
        }
        #endif

        var initiated: HandshakeStateMachine.InitiatedState = previousHandshake
        initiated.onConnectionEstablished(channel: channel)

        self.handshakesByEndpoint[initiated.remoteEndpoint] = .initiated(initiated)
        return self
    }

    internal func handshakeInProgress(with endpoint: Cluster.Endpoint) -> HandshakeStateMachine.State? {
        self.handshakesByEndpoint[endpoint]
    }

    /// Abort a handshake, clearing any of its state as well as closing the passed in channel
    /// (which should be the one which the handshake to abort was made on).
    ///
    /// - Faults: when called in wrong state of an ongoing handshake
    /// - Returns: if present, the (now removed) handshake state that was aborted, hil otherwise.
    internal mutating func closeOutboundHandshakeChannel(
        with endpoint: Cluster.Endpoint
    ) -> HandshakeStateMachine.State? {
        guard let state = self.handshakesByEndpoint.removeValue(forKey: endpoint) else {
            return nil
        }
        switch state {
        case .initiated(let initiated):
            if let channel = initiated.channel {
                self.log.trace("Aborting OUTBOUND handshake channel: \(channel)")

                channel.close().whenFailure { [log = self.log] error in
                    log.debug("Failed to abortOutgoingHandshake (close) channel [\(channel)], error: \(error)")
                }
            }  // else, no channel to close?

        case .wasOfferedHandshake:
            fatalError(
                """
                abortOutgoingHandshake was called in a context where the handshake was not an outgoing one! \
                Was: \(state)
                """
            )

        case .completed:
            fatalError(
                """
                Attempted to abort an already completed handshake; \
                Completed should never remain stored; Was: \(state)
                """
            )

        case .inFlight:
            fatalError("Stored state was .inFlight, which should never be stored: \(state)")
        }

        return state
    }

    /// Abort an incoming handshake channel;
    /// As there may be a concurrent negotiation ongoing on another (outgoing) connection, we do NOT remove the
    /// handshake
    /// by node from the handshakesByEndpoint.
    ///
    /// - Returns: if present, the (now removed) handshake state that was aborted, hil otherwise.
    internal mutating func closeHandshakeChannel(offer _: Wire.HandshakeOffer, channel: Channel) {
        self.log.trace("Aborting INBOUND handshake channel: \(channel)")

        channel.close().whenFailure { [log = self.log, metadata = self.metadata] error in
            switch error {
            case ChannelError.alreadyClosed:
                // this is less severe and we should not warn about it; most often it's just a race of closes when we're
                // racing both sides connecting.
                log.debug("Channel already closed [\(channel)], error: \(error)", metadata: metadata)

            default:
                log.warning("Failed to close channel [\(channel)], error: \(error)", metadata: metadata)
            }
        }
    }

    /// This is the entry point for a server receiving a handshake with a remote node.
    /// Inspects and possibly allocates a `HandshakeStateMachine` in the `HandshakeReceivedState` state.
    ///
    /// Scenarios:
    ///   L - local node
    ///   R - remote node
    ///
    ///   L initiates connection to R; R initiates connection to L;
    ///   Both nodes store an `initiated` state for the handshake; both will receive the others offer;
    ///   We need to perform a tie-break to see which one should actually "drive" this connecting: we pick the "lower
    /// node".
    ///
    ///   Upon tie-break the nodes follow these two roles:
    ///     Winner: Keeps the outgoing connection, negotiates and replies accept/reject on the "incoming" connection
    /// from the remote node.
    ///     Loser: Drops the incoming connection and waits for Winner's decision.
    internal mutating func onIncomingHandshakeOffer(
        offer: Wire.HandshakeOffer, existingAssociation: Association?, incomingChannel: Channel
    ) -> OnIncomingHandshakeOfferDirective {
        if let abort = self.abortForExistingAssociation(existingAssociation, offer: offer) {
            return abort
        }
        guard let inProgress = self.handshakesByEndpoint[offer.originNode.endpoint] else {
            return self.prepareIncomingNegotiation(offer)
        }
        switch inProgress {
        case .initiated(let initiated):
            return self.resolveConcurrentHandshake(initiated, offer: offer, incomingChannel: incomingChannel)

        case .wasOfferedHandshake:
            return self.prepareIncomingNegotiation(offer)

        case .inFlight(let inFlight):
            fatalError(
                """
                inFlight state [\(inFlight)] should never have been stored as handshake state; \
                This is likely a bug, please open an issue.
                """
            )

        case .completed(let completed):
            fatalError(
                """
                completed state [\(completed)] should never have been stored as handshake state; \
                This is likely a bug, please open an issue.
                """
            )
        }
    }

    private mutating func prepareIncomingNegotiation(
        _ offer: Wire.HandshakeOffer
    ) -> OnIncomingHandshakeOfferDirective {
        let received: HandshakeStateMachine.HandshakeOfferReceivedState = .init(state: self, offer: offer)
        self.handshakesByEndpoint[offer.originNode.endpoint] = .wasOfferedHandshake(received)
        return .negotiateIncoming(received)
    }

    private func abortForExistingAssociation(
        _ association: Association?, offer: Wire.HandshakeOffer
    ) -> OnIncomingHandshakeOfferDirective? {
        guard let association = association else {
            return nil
        }
        let stateDescription: String
        switch association.state {
        case .associating:
            return nil

        case .associated:
            stateDescription = "associated"

        case .tombstone:
            stateDescription = "tombstone-ed"
        }
        let failure: HandshakeStateMachine.HandshakeConnectionError = .init(
            endpoint: offer.originNode.endpoint,
            message: """
                Terminating this connection, the node [\(offer.originNode)] is already \(stateDescription). \
                Possibly a delayed handshake retry message was delivered?
                """
        )
        return .abortIncomingHandshake(failure)
    }

    private mutating func resolveConcurrentHandshake(
        _ initiated: HandshakeStateMachine.InitiatedState,
        offer: Wire.HandshakeOffer,
        incomingChannel: Channel
    ) -> OnIncomingHandshakeOfferDirective {
        // Both nodes use the same address order to choose which connection negotiates.
        let tieBreakWinner: Bool = initiated.localNode < offer.originNode
        self.log.debug(
            """
            Concurrently initiated handshakes from nodes [\(initiated.localNode)](local) and \
            [\(offer.originNode)](remote) detected! Resolving race by address ordering; \
            This node \(tieBreakWinner ? "WON (will negotiate and reply)" : "LOST (will await reply)") tie-break.
            """,
            metadata: [
                "handshake/inProgress": "\(initiated)",
                "handshake/incoming/offer": "\(offer)",
                "handshake/incoming/channel": "\(incomingChannel)",
            ]
        )
        if tieBreakWinner {
            if self.closeOutboundHandshakeChannel(with: offer.originNode.endpoint) != nil {
                self.log.debug(
                    "Aborted handshake, as concurrently negotiating another one with same node already",
                    metadata: ["handshake/status": "abort-incoming,offer", "handshake/from": "\(offer.originNode)"]
                )
            }
            return self.prepareIncomingNegotiation(offer)
        }
        let failure: HandshakeStateMachine.HandshakeConnectionError = .init(
            endpoint: offer.originNode.endpoint,
            message: """
                Terminating this connection, as there is a concurrently established connection with same host \
                [\(offer.originNode)] which will be used to complete the handshake.
                """
        )
        return .abortIncomingHandshake(failure)
    }

    internal mutating func incomingHandshakeAccept(
        _ accept: Wire.HandshakeAccept
    ) -> HandshakeStateMachine.CompletedState? {
        guard let inProgressHandshake = self.handshakesByEndpoint[accept.targetNode.endpoint] else {
            self.log.warning(
                "Attempted to accept incoming [\(accept)] for handshake which was not in progress!",
                metadata: [
                    "clusterShell": "\(self)",
                    "membership": "\(self.membership)",
                ]
            )
            return nil
        }

        switch inProgressHandshake {
        case .initiated(let hsm):
            return HandshakeStateMachine.CompletedState(fromInitiated: hsm, remoteNode: accept.targetNode)

        case .wasOfferedHandshake:
            self.log.warning("Received accept but state machine is in WAS OFFERED state. This should be impossible.")
            return nil

        case .completed:
            self.log.warning("Received handshake Accept for already completed handshake. This should not happen.")
            return nil

        case .inFlight:
            fatalError("An in-flight marker state should never be stored, yet was encountered in \(#function)")
        }
    }

    /// "Upgrades" a connection with a remote node from handshaking state to associated.
    /// Stores an `Association` for the newly established association;
    ///
    /// Does NOT by itself move the member to joining, but via the directive asks the outer to do this.
    internal mutating func completeHandshakeAssociate(
        _: ClusterShell,
        _ handshake: HandshakeStateMachine.CompletedState,
        channel: Channel
    ) -> AssociatedDirective {
        guard self.handshakesByEndpoint.removeValue(forKey: handshake.remoteNode.endpoint) != nil else {
            fatalError("Can not complete a handshake which was not in progress!")
        }

        let change: Cluster.MembershipChange?
        if let replacedMember = self.membership.anyMember(forEndpoint: handshake.remoteNode.endpoint) {
            change = self.membership.applyMembershipChange(.init(
                replaced: replacedMember, by: .init(node: handshake.remoteNode, status: .joining)
            ))
        } else {
            change = self.membership.applyMembershipChange(.init(
                member: .init(node: handshake.remoteNode, status: .joining)
            ))
        }

        return AssociatedDirective(
            membershipChange: change,
            handshake: handshake,
            channel: channel
        )
    }
}
