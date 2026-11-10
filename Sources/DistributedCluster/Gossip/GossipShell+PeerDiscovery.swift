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

extension GossipShell {
    private func resolveInsertPeer(
        _ context: ActorContext<Message>,
        member: Cluster.Member,
        atLeastStatus: Cluster.MemberStatus,
        resolvePeerOn: (Cluster.Member) -> AddressableActorRef
    ) {
        guard member.node != context.system.cluster.node else {
            return  // ignore self node
        }

        guard atLeastStatus <= member.status else {
            return  // too "early" status of the member
        }

        let resolved: AddressableActorRef = resolvePeerOn(member)
        if let peer = resolved.ref as? PeerRef {
            // We MUST always watch all peers we gossip with, as if they (or their nodes) were to terminate
            // they MUST be removed from the peer list we offer to gossip logics. Otherwise a naive gossip logic
            // may continue trying to gossip with that peer.
            context.watch(peer)

            if self.peers.insert(peer).inserted {
                context.log.debug(
                    "Automatically discovered peer",
                    metadata: [
                        "gossip/peer": "\(peer)",
                        "gossip/peerCount": "\(self.peers.count)",
                        "gossip/peers": "\(self.peers.map(\.id))",
                    ]
                )
            }
        } else {
            context.log.warning(
                "Resolved reference \(resolved.ref) is not \(PeerRef.self), can not use it as peer for gossip."
            )
        }
    }

    internal func initPeerDiscovery(_ context: ActorContext<Message>) {
        switch self.settings.peerDiscovery {
        case .manuallyIntroduced:
            return  // nothing to do, peers will be introduced manually

        case let .onClusterMember(atLeastStatus, resolvePeerOn):

            let onClusterEventRef: ActorRef<Cluster.Event> = context.subReceive(Cluster.Event.self) { event in
                switch event {
                case .snapshot(let membership):
                    for member in membership.members(atLeast: .joining) {
                        self.resolveInsertPeer(
                            context,
                            member: member,
                            atLeastStatus: atLeastStatus,
                            resolvePeerOn: resolvePeerOn
                        )
                    }

                case .membershipChange(let change):
                    self.resolveInsertPeer(
                        context,
                        member: change.member,
                        atLeastStatus: atLeastStatus,
                        resolvePeerOn: resolvePeerOn
                    )

                case .leadershipChange, .reachabilityChange:
                    ()  // ignore

                case .nonExhaustive:
                    context.log.error(
                        "Received Cluster.Event [\(event)]. This should not happen, please file an issue."
                    )
                }
            }
            context.system.cluster.events.subscribe(onClusterEventRef)

        case .fromReceptionistListing(let id):
            self.discoverReceptionistPeers(context, id: id)
        }
    }

    internal func onIntroducePeer(_ context: ActorContext<Message>, peer: PeerRef) {
        guard peer != context.myself else {
            return  // there is never a need to gossip to myself
        }

        if self.peers.insert(context.watch(peer)).inserted {
            context.log.trace(
                "Got introduced to peer [\(peer)]",
                metadata: [
                    "gossip/peerCount": "\(self.peers.count)",
                    "gossip/peers": "\(self.peers.map(\.id))",
                ]
            )

            self.ensureNextGossipRound(context)
        }
    }

    private func discoverReceptionistPeers(_ context: ActorContext<Message>, id: String) {
        let key: Reception.Key<ActorRef<Message>> = Reception.Key(ActorRef<Message>.self, id: id)
        context.receptionist.registerMyself(with: key, replyTo: nil)
        context.log.debug("Registered with receptionist key: \(key)")

        context.receptionist.subscribeMyself(
            to: key
        ) { listing in
            context.log.trace(
                "Peer listing update via receptionist",
                metadata: [
                    "peer/listing": Logger.MetadataValue.array(
                        listing.refs.map { ref in Logger.MetadataValue.stringConvertible(ref) }
                    ),
                ]
            )
            for peer in listing.refs {
                self.onIntroducePeer(context, peer: peer)
            }
        }
    }
}
