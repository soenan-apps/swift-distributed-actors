// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Logging

private let kGossipTickKey: TimerKey = "gossip-tick"

/// Not intended to be spawned directly, use `Gossiper.spawn` instead!
internal final class GossipShell<Gossip: Codable, Acknowledgement: Codable> {
    internal typealias Ref = ActorRef<Message>

    internal typealias PeerRef = ActorRef<Message>

    internal enum SideChannelDirective {
        case received
        case unhandled
    }

    internal enum Message {
        // gossip
        case gossip(identity: GossipIdentifier, origin: ActorRef<Self>, Gossip, ackRef: ActorRef<Acknowledgement>?)

        // local messages
        case updatePayload(identifier: GossipIdentifier, Gossip)
        case removePayload(identifier: GossipIdentifier)
        case introducePeer(PeerRef)

        case sideChannelMessage(identifier: GossipIdentifier, Any)

        // internal messages
        case periodicGossipTick
    }

    internal let settings: GossiperSettings

    private let makeLogic: (ActorContext<Message>, GossipIdentifier) -> AnyGossipLogic<Gossip, Acknowledgement>

    /// Payloads to be gossiped on gossip rounds
    private var gossipLogics: [AnyGossipIdentifier: AnyGossipLogic<Gossip, Acknowledgement>]
    internal var peers: Set<PeerRef>

    internal var behavior: Behavior<Message> {
        .setup { context in
            self.ensureNextGossipRound(context)
            self.initPeerDiscovery(context)
            return Behavior<Message>.receiveMessage { message in
                self.handleMessage(context, message)
            }.receiveSpecificSignal(Signals.Terminated.self) { signalContext, terminated in
                signalContext.log.trace("Peer terminated: \(terminated.id), will not gossip to it anymore")
                self.peers = self.peers.filter { peer in peer.id != terminated.id }
                if self.peers.isEmpty {
                    signalContext.log.trace("No peers available, cancelling periodic gossip timer")
                    signalContext.timers.cancel(for: kGossipTickKey)
                }
                return .same
            }
        }
    }

    internal init<Logic>(
        settings: GossiperSettings,
        makeLogic: @escaping (Logic.Context) -> Logic
    ) where Logic: GossipLogic, Logic.Gossip == Gossip, Logic.Acknowledgement == Acknowledgement {
        self.settings = settings
        self.makeLogic = { shellContext, id in
            let logicContext: GossipLogicContext<Gossip, Acknowledgement> = GossipLogicContext(
                ownerContext: shellContext,
                gossipIdentifier: id
            )
            let logic: Logic = makeLogic(logicContext)
            return AnyGossipLogic(logic)
        }
        self.gossipLogics = [:]
        self.peers = []
    }

    internal static func receptionKey(id: String) -> Reception.Key<ActorRef<Message>> {
        Reception.Key(id: id)
    }

    private func handleMessage(_ context: ActorContext<Message>, _ message: Message) -> Behavior<Message> {
        switch message {
        case let .updatePayload(identifier, payload):
            self.onLocalPayloadUpdate(context, identifier: identifier, payload: payload)

        case .removePayload(let identifier):
            self.onLocalPayloadRemove(context, identifier: identifier)

        case .introducePeer(let peer):
            self.onIntroducePeer(context, peer: peer)

        case let .sideChannelMessage(identifier, payload):
            switch self.onSideChannelMessage(context, identifier: identifier, payload) {
            case .received:
                break

            case .unhandled:
                return .unhandled
            }

        case let .gossip(identity, origin, payload, ackRef):
            self.receiveGossip(context, identifier: identity, origin: origin, payload: payload, ackRef: ackRef)

        case .periodicGossipTick:
            self.runGossipRound(context)
        }
        return .same
    }

    private func receiveGossip(
        _ context: ActorContext<Message>,
        identifier: GossipIdentifier,
        origin: ActorRef<Message>,
        payload: Gossip,
        ackRef: ActorRef<Acknowledgement>?
    ) {
        context.log.trace(
            "Received gossip [\(identifier.gossipIdentifier)]",
            metadata: [
                "gossip/identity": "\(identifier.gossipIdentifier)",
                "gossip/origin": "\(origin.id)",
                "gossip/incoming": Logger.MetadataValue.pretty(payload),
            ]
        )

        let logic: AnyGossipLogic<Gossip, Acknowledgement> = self.getEnsureLogic(context, identifier: identifier)

        let ack: Acknowledgement? = logic.receiveGossip(payload, from: origin.asAddressable)

        switch self.settings.style {
        case .acknowledged:
            if let ack = ack {
                ackRef?.tell(ack)
            }

        case .unidirectional:
            if let unexpectedAck = ack {
                context.log.warning(
                    """
                    GossipLogic attempted to offer Acknowledgement while it is configured as .unidirectional!\
                    This is potentially a bug in the logic or the Gossiper's configuration. Dropping acknowledgement.
                    """,
                    metadata: [
                        "gossip/identity": "\(identifier.gossipIdentifier)",
                        "gossip/origin": "\(origin.id)",
                        "gossip/ack": "\(unexpectedAck)",
                    ]
                )
            }
            if let unexpectedAckRef = ackRef {
                context.log.warning(
                    """
                    Incoming gossip expects an ACK, while this gossiper is configured as .unidirectional! \
                    This is potentially a bug in the logic or the Gossiper's configuration.
                    """,
                    metadata: [
                        "gossip/identity": "\(identifier.gossipIdentifier)",
                        "gossip/origin": "\(origin.id)",
                        "gossip/ackRef": "\(unexpectedAckRef)",
                    ]
                )
            }
        }
    }

    private func onLocalPayloadUpdate(
        _ context: ActorContext<Message>,
        identifier: GossipIdentifier,
        payload: Gossip
    ) {
        let logic: AnyGossipLogic<Gossip, Acknowledgement> = self.getEnsureLogic(context, identifier: identifier)

        context.log.trace(
            "Update (locally) gossip payload [\(identifier.gossipIdentifier)]",
            metadata: [
                "gossip/identifier": "\(identifier.gossipIdentifier)",
                "gossip/payload": .string("\(pretty: payload)"),
            ]
        )
        logic.receiveLocalGossipUpdate(payload)
    }

    private func getEnsureLogic(
        _ context: ActorContext<Message>,
        identifier: GossipIdentifier
    ) -> AnyGossipLogic<Gossip, Acknowledgement> {
        let logic: AnyGossipLogic<Gossip, Acknowledgement>
        if let existing = self.gossipLogics[identifier.asAnyGossipIdentifier] {
            logic = existing
        } else {
            logic = self.makeLogic(context, identifier)
            self.gossipLogics[identifier.asAnyGossipIdentifier] = logic
        }
        return logic
    }

    // keep and remove logics
    private func onLocalPayloadRemove(_ context: ActorContext<Message>, identifier: GossipIdentifier) {
        let identifierKey: AnyGossipIdentifier = identifier.asAnyGossipIdentifier

        _ = self.gossipLogics.removeValue(forKey: identifierKey)
        context.log.trace(
            "Removing gossip identified by [\(identifier)]",
            metadata: [
                "gossip/identifier": "\(identifier)"
            ]
        )

        // callback into client or not?
    }

    private func onSideChannelMessage(
        _ context: ActorContext<Message>,
        identifier: GossipIdentifier,
        _ message: Any
    ) -> SideChannelDirective {
        guard let logic = self.gossipLogics[identifier.asAnyGossipIdentifier] else {
            return .unhandled
        }

        do {
            try logic.receiveSideChannelMessage(message)
        } catch {
            context.log.error("Gossip logic \(logic) [\(identifier)] receiveSideChannelMessage failed: \(error)")
            return .received
        }

        return .received
    }
}

extension GossipShell {
    private func runGossipRound(_ context: ActorContext<Message>) {
        defer {
            self.ensureNextGossipRound(context)
        }

        let allPeers: [AddressableActorRef] = Array(self.peers).map(\.asAddressable)

        guard !allPeers.isEmpty else {
            // no members to gossip with, skip this round
            return
        }

        for (identifier, logic) in self.gossipLogics {
            let selectedPeers: [AddressableActorRef] = logic.selectPeers(allPeers)

            context.log.trace(
                "New gossip round, selected [\(selectedPeers.count)] peers, from [\(allPeers.count)] peers",
                metadata: [
                    "gossip/id": "\(identifier.gossipIdentifier)",
                    "gossip/peers/selected": Logger.MetadataValue.array(selectedPeers.map { "\($0)" }),
                ]
            )

            for selectedPeer in selectedPeers {
                guard let gossip: Gossip = logic.makePayload(target: selectedPeer) else {
                    context.log.trace(
                        "Skipping gossip to peer \(selectedPeer)",
                        metadata: [
                            "gossip/id": "\(identifier.gossipIdentifier)",
                            "gossip/target": "\(selectedPeer)",
                        ]
                    )
                    continue
                }

                // a bit annoying that we have to do this dance, but we don't want to let the logic do the sending,
                // types would be wrong, and logging and more lost
                guard let selectedRef = selectedPeer.ref as? PeerRef else {
                    context.log.trace(
                        "Selected peer \(selectedPeer) is not of \(PeerRef.self) type; skipping unknown gossip actor.",
                        metadata: [
                            "gossip/id": "\(identifier.gossipIdentifier)",
                            "gossip/target": "\(selectedPeer)",
                        ]
                    )
                    continue
                }

                self.sendGossip(
                    context,
                    identifier: identifier,
                    gossip,
                    to: selectedRef
                ) { acknowledgement in
                    logic.receiveAcknowledgement(acknowledgement, from: selectedPeer, confirming: gossip)
                }
            }

            // signal "gossip round complete" perhaps?
            // it would allow for "speed up" rounds, as well as "remove me, we're done"
        }
    }

    private func sendGossip(
        _ context: ActorContext<Message>,
        identifier: AnyGossipIdentifier,
        _ payload: Gossip,
        to target: PeerRef,
        onGossipAck: @escaping (Acknowledgement) -> Void
    ) {
        context.log.trace(
            "Sending gossip to \(target.id)",
            metadata: [
                "gossip/target": "\(target.id)",
                "gossip/peers/count": "\(self.peers.count)",
                "actor/message": Logger.MetadataValue.pretty(payload),
            ]
        )

        switch self.settings.style {
        case .unidirectional:
            target.tell(Message.gossip(identity: identifier.underlying, origin: context.myself, payload, ackRef: nil))

        case .acknowledged(let timeout):
            let response: AskResponse<Acknowledgement> = target.ask(timeout: timeout) { replyTo in
                Message.gossip(identity: identifier.underlying, origin: context.myself, payload, ackRef: replyTo)
            }

            context.onResultAsync(of: response, timeout: .effectivelyInfinite) { res in
                switch res {
                case .success(let ack):
                    context.log.trace(
                        "Gossip ACKed",
                        metadata: [
                            "gossip/ack": "\(ack)"
                        ]
                    )
                    onGossipAck(ack)

                case .failure(let error):
                    context.log.debug(
                        "Did not receive ACK for of [\(identifier.gossipIdentifier)] gossip",
                        metadata: [
                            "payload": "\(payload)",
                            "target": "\(target)",
                            "error": "\(error)",
                        ]
                    )
                }
                return .same
            }
        }
    }

    internal func ensureNextGossipRound(_ context: ActorContext<Message>) {
        guard !self.peers.isEmpty else {
            return  // no need to schedule gossip ticks if we have no peers
        }

        let delay: Duration = self.settings.effectiveInterval
        context.log.trace(
            """
            Schedule next gossip round in \(delay.prettyDescription) \
            (\(self.settings.interval.prettyDescription) ± \(self.settings.intervalRandomFactor * 100)%)
            """
        )
        context.timers.startSingle(key: kGossipTickKey, message: .periodicGossipTick, delay: delay)
    }
}
