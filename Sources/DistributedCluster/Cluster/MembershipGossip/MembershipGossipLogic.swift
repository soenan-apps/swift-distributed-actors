// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import NIO

/// The logic of the membership gossip.
///
/// Membership gossip is what is used to reach cluster "convergence" upon which a leader may perform leader actions.
/// See `Cluster.MembershipGossip.converged` for more details.
internal final class MembershipGossipLogic: GossipLogic, CustomStringConvertible {
    internal typealias Gossip = Cluster.MembershipGossip
    internal typealias Acknowledgement = Cluster.MembershipGossip

    internal struct PeersChanged {
        internal let added: Set<AddressableActorRef>
        internal let removed: Set<AddressableActorRef>

        internal init(added: Set<AddressableActorRef>, removed: Set<AddressableActorRef>) {
            assert(!added.isEmpty || !removed.isEmpty, "PeersChanged yet both added/removed are empty!")
            self.added = added
            self.removed = removed
        }
    }

    private let context: Context
    internal lazy var localNode: Cluster.Node = self.context.system.cluster.node

    internal var latestGossip: Cluster.MembershipGossip
    private let notifyOnGossipRef: ActorRef<Cluster.MembershipGossip>

    /// We store and use a shuffled yet stable order for gossiping peers.
    /// See `updateActivePeers` for details.
    private var peers: [AddressableActorRef] = []
    /// Constantly mutated by `nextPeerToGossipWith` in an effort to keep order in which we gossip with nodes evenly
    /// distributed.
    /// This follows our logic in SWIM, and has the benefit that we never get too chatty with one specific node (as in
    /// the worst case it may be unreachable or down already).
    private var _peerToGossipWithIndex: Int = 0

    /// During 1:1 gossip interactions, update this table, which means "we definitely know the specific node has seen
    /// our version VV at ..."
    ///
    /// See `updateActivePeers` and `receiveGossip` for details.
    private var lastGossipFrom: [AddressableActorRef: Cluster.MembershipGossip] = [:]

    internal var description: String {
        "MembershipGossipLogic(\(self.localNode))"
    }

    internal init(_ context: Context, notifyOnGossipRef: ActorRef<Cluster.MembershipGossip>) {
        self.context = context
        self.notifyOnGossipRef = notifyOnGossipRef
        self.latestGossip = .init(ownerNode: context.system.cluster.node)
    }

    // MARK: Spreading gossip

    internal static func peersChanged(known: [AddressableActorRef], current: [AddressableActorRef]) -> PeersChanged? {
        let knownSet: Set<AddressableActorRef> = Set(known)
        let currentSet: Set<AddressableActorRef> = Set(current)

        let added: Set<AddressableActorRef> = currentSet.subtracting(knownSet)
        let removed: Set<AddressableActorRef> = knownSet.subtracting(currentSet)

        if added.isEmpty, removed.isEmpty {
            return nil
        }
        return PeersChanged(
            added: added,
            removed: removed
        )
    }

    internal func selectPeers(_ peers: [AddressableActorRef]) -> [AddressableActorRef] {
        // how many peers we select in each gossip round,
        // we could for example be dynamic and notice if we have 10+ nodes, we pick 2 members to speed up the
        // dissemination etc.
        let peerLimit: Int = 1

        self.updateActivePeers(peers)
        var selectedPeers: [AddressableActorRef] = []
        selectedPeers.reserveCapacity(min(peerLimit, self.peers.count))

        // Trust the order of peers in gossipPeers for the selection; see `updateActivePeers` for logic of the
        // ordering.
        for peer in self.peers where selectedPeers.count < peerLimit {
            if self.shouldGossipWith(peer) {
                selectedPeers.append(peer)
            }
        }

        return selectedPeers
    }

    private func updateActivePeers(_ peers: [AddressableActorRef]) {
        if let changed = Self.peersChanged(known: self.peers, current: peers) {
            // 1) remove any peers which are no longer active
            //    - from the peers list
            //    - from their gossip storage, we'll never gossip with them again after all
            if !changed.removed.isEmpty {
                let removedPeers: Set<AddressableActorRef> = Set(changed.removed)
                self.peers = self.peers.filter { !removedPeers.contains($0) }
                for removedPeer in changed.removed {
                    _ = self.lastGossipFrom.removeValue(forKey: removedPeer)
                }
            }

            for peer in changed.added {
                // Newly added members are inserted at a random spot in the list of members
                // to ping, to have a better distribution of messages to this node from all
                // other nodes. If for example all nodes would add it to the end of the list,
                // it would take a longer time until it would be pinged for the first time
                // and also likely receive multiple pings within a very short time frame.
                //
                // This is adopted from the SWIM membership implementation and related papers.
                let insertIndex: Int = Int.random(in: self.peers.startIndex...self.peers.endIndex)
                self.peers.insert(peer, at: insertIndex)
            }
        }
    }

    internal func makePayload(target _: AddressableActorRef) -> Cluster.MembershipGossip? {
        // today we don't trim payloads at all
        self.latestGossip
    }

    /// True if the peers is "behind" in terms of information it has "seen" (as determined by comparing our and its seen
    /// tables). This hardens the implementation against gossiping with the same node multiple times in a row.
    /// Dead-peer filtering is handled by the gossip shell.
    private func shouldGossipWith(_ peer: AddressableActorRef) -> Bool {
        guard let lastSeenGossipFromPeer = self.lastGossipFrom[peer] else {
            // it's a peer we have not gotten any gossip from yet
            return true
        }

        return self.latestGossip.seen != lastSeenGossipFromPeer.seen
    }

    // MARK: Receiving gossip

    internal func receiveGossip(_ gossip: Gossip, from peer: AddressableActorRef) -> Acknowledgement? {
        // 1) mark that from that specific peer, we know it observed at least that version
        self.lastGossipFrom[peer] = gossip

        // 2) move forward the gossip we store
        self.mergeInbound(gossip: gossip)

        // 3) notify listeners
        self.notifyOnGossipRef.tell(self.latestGossip)

        // no need to send back the entire tables if it's the same up to date ones as we just received
        return self.latestGossip
    }

    internal func receiveAcknowledgement(
        _ acknowledgement: Acknowledgement,
        from peer: AddressableActorRef,
        confirming _: Cluster.MembershipGossip
    ) {
        // 1) store the direct gossip we got from this peer; we can use this to know if there's no need to gossip to
        // that peer by inspecting seen table equality
        self.lastGossipFrom[peer] = acknowledgement

        // 2) move forward the gossip we store
        self.mergeInbound(gossip: acknowledgement)

        // 3) notify listeners
        self.notifyOnGossipRef.tell(self.latestGossip)
    }

    internal func receiveLocalGossipUpdate(_ gossip: Cluster.MembershipGossip) {
        self.mergeInbound(gossip: gossip)
    }

    // MARK: Utilities

    private func mergeInbound(gossip: Cluster.MembershipGossip) {
        _ = self.latestGossip.mergeForward(incoming: gossip)
        // effects are signalled via the ClusterShell, not here (it will also perform a merge)
    }

}
