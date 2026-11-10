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

/// Arbitrary gossip logic, used to drive the `GossipShell` which performs the actual gossiping.
///
/// Each logic owns one gossip identity and selects peers and payloads for each round.
/// Receiving gossip can update that state and optionally produce an acknowledgement.
/// Peer selection may skip nodes that have already observed every available update.
///
/// - SeeAlso: [Gossiping in Distributed Systems](https://www.distributed-systems.net/my-data/papers/2007.osr.pdf)
/// - SeeAlso: `Cluster.Gossip` for the Actor System's own gossip mechanism for membership dissemination
internal protocol GossipLogic {
    associatedtype Gossip: Codable
    associatedtype Acknowledgement: Codable

    typealias Context = GossipLogicContext<Gossip, Acknowledgement>

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Spreading gossip

    // OrderedSet would be the right thing here to be honest...
    /// Invoked by the gossiper actor during a gossip round.
    ///
    /// Useful to implement using `PeerSelection`
    mutating func selectPeers(_ peers: [AddressableActorRef]) -> [AddressableActorRef]
    // make a directive here

    /// Allows for customizing the payload for each of the selected peers.
    ///
    /// Some gossip protocols are able to specialize the gossip payload sent to a specific peer,
    /// e.g. by excluding information the peer is already aware of or similar.
    ///
    /// Returning nil skips the selected peer for this gossip round.
    mutating func makePayload(target: AddressableActorRef) -> Gossip?

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Receiving gossip

    /// Invoked whenever a gossip message is received from another peer.
    ///
    /// Note that a single gossiper instance may create _multiple_ `GossipLogic` instances,
    /// one for each `GossipIdentifier` it is managing. This function is guaranteed to be invoked with the
    /// gossip targeted to the same gossip identity as the logic's context
    mutating func receiveGossip(_ gossip: Gossip, from peer: AddressableActorRef) -> Acknowledgement?

    /// Invoked when the specific gossiped payload is acknowledged by the target.
    ///
    /// Acknowledgements may arrive in any order, or may never arrive.
    /// Eg. if gossip is sent to 2 peers, it is NOT deterministic which of the acks returns first (or at all!).
    ///
    /// - Parameters:
    ///   - acknowledgement: acknowledgement sent by the peer
    ///   - peer: The target which has acknowledged the gossiped payload.
    ///     This is the peer passed to `makePayload(target:)`.
    ///   - gossip: The payload being acknowledged.
    mutating func receiveAcknowledgement(
        _ acknowledgement: Acknowledgement,
        from peer: AddressableActorRef,
        confirming gossip: Gossip
    )

    // MARK: Local interactions

    mutating func receiveLocalGossipUpdate(_ gossip: Gossip)

    /// Extra side channel, allowing for arbitrary outside interactions with this gossip logic.
    mutating func receiveSideChannelMessage(_ message: Any) throws
}

extension GossipLogic {
    internal mutating func receiveAcknowledgement(
        _: Acknowledgement, from _: AddressableActorRef, confirming _: Gossip
    ) {
        // ignore by default
    }

    internal mutating func receiveSideChannelMessage(_: Any) {
        // ignore by default
    }
}
