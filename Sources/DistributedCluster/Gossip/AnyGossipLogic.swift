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

internal struct AnyGossipLogic<Gossip: Codable, Acknowledgement: Codable>: GossipLogic, CustomStringConvertible {
    @usableFromInline internal let selectPeersImpl: ([AddressableActorRef]) -> [AddressableActorRef]
    @usableFromInline internal let makePayloadImpl: (AddressableActorRef) -> Gossip?
    @usableFromInline internal let receiveGossipImpl: (Gossip, AddressableActorRef) -> Acknowledgement?
    @usableFromInline internal let receiveAcknowledgementImpl: (Acknowledgement, AddressableActorRef, Gossip) -> Void

    @usableFromInline internal let receiveLocalGossipUpdateImpl: (Gossip) -> Void
    @usableFromInline internal let receiveSideChannelMessageImpl: (Any) throws -> Void

    internal var description: String {
        "\(reflecting: Self.self)(...)"
    }

    internal init<Logic>(_ logic: Logic)
    where Logic: GossipLogic, Logic.Gossip == Gossip, Logic.Acknowledgement == Acknowledgement {
        var statefulLogic: Logic = logic
        self.selectPeersImpl = { statefulLogic.selectPeers($0) }
        self.makePayloadImpl = { statefulLogic.makePayload(target: $0) }
        self.receiveGossipImpl = { statefulLogic.receiveGossip($0, from: $1) }

        self.receiveAcknowledgementImpl = { statefulLogic.receiveAcknowledgement($0, from: $1, confirming: $2) }
        self.receiveLocalGossipUpdateImpl = { statefulLogic.receiveLocalGossipUpdate($0) }

        self.receiveSideChannelMessageImpl = { try statefulLogic.receiveSideChannelMessage($0) }
    }

    internal func selectPeers(_ peers: [AddressableActorRef]) -> [AddressableActorRef] {
        self.selectPeersImpl(peers)
    }

    internal func makePayload(target: AddressableActorRef) -> Gossip? {
        self.makePayloadImpl(target)
    }

    internal func receiveGossip(_ gossip: Gossip, from peer: AddressableActorRef) -> Acknowledgement? {
        self.receiveGossipImpl(gossip, peer)
    }

    internal func receiveAcknowledgement(
        _ acknowledgement: Acknowledgement,
        from peer: AddressableActorRef,
        confirming gossip: Gossip
    ) {
        self.receiveAcknowledgementImpl(acknowledgement, peer, gossip)
    }

    internal func receiveLocalGossipUpdate(_ gossip: Gossip) {
        self.receiveLocalGossipUpdateImpl(gossip)
    }

    internal func receiveSideChannelMessage(_ message: Any) throws {
        try self.receiveSideChannelMessageImpl(message)
    }
}
