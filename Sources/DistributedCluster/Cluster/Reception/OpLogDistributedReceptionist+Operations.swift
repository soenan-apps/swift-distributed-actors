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

import AsyncAlgorithms
import CoreMetrics
import Distributed
import Logging
import OrderedCollections

extension OpLogDistributedReceptionist {
    // MARK: Handling Ops

    /// Received a push of ops; apply them to the local view of the key space (storage).
    ///
    /// The incoming ops will be until some max SeqNr, once we have applied them all,
    /// we send back an `ack(maxSeqNr)` to both confirm the receipt, as well as potentially trigger
    /// more ops being delivered
    internal distributed func pushOps(_ push: PushOps) {
        let peer: ReceptionistRef = push.peer

        // 1.1) apply the pushed ops to our state
        let peerReplicaId: ReplicaID = .actorID(push.peer.id)
        let lastAppliedSeqNrAtPeer: UInt64 = self.appliedSequenceNrs[peerReplicaId]

        // De-duplicate
        // In case we got re-sends (the other node sent us some data twice, yet we already have it, we do not
        // replay the already known data),
        // we do not want to apply the same ops twice, so we skip the already known ones
        let opsToApply: ArraySlice<OpLog<ReceptionistOp>.SequencedOp> = push.sequencedOps.drop { operation in
            operation.sequenceRange.max <= lastAppliedSeqNrAtPeer
        }

        self.log.trace(
            "Received \(push.sequencedOps.count) ops",
            metadata: [
                "receptionist/peer": "\(push.peer.id)",
                "receptionist/lastKnownSeqNrAtPeer": "\(lastAppliedSeqNrAtPeer)",
                "receptionist/opsToApply": Logger.Metadata.Value.array(
                    opsToApply.map { Logger.Metadata.Value.string("\($0)") }
                ),
            ]
        )

        // Collect which keys have been updated during this push, so we can publish updated listings for them.
        var keysToPublish: Set<AnyDistributedReceptionKey> = []
        for operation in opsToApply {
            keysToPublish.insert(self.applyIncomingOp(from: peer, operation))
        }

        self.log.trace("Keys to publish: \(keysToPublish)")

        // 1.2) update our observed version of `pushed.peer` to the incoming
        self.observedSequenceNrs.merge(other: push.observedSeqNrs)
        self.appliedSequenceNrs.merge(other: .init(push.findMaxSequenceNr(), at: peerReplicaId))

        // 2) check for all peers if we are "behind", and should pull information from them
        //    if this message indicated "end" of the push, then we assume we are up to date with it
        //    and will only pull again from it on the SlowACK
        let myselfReplicaID: ReplicaID = .actorID(self.id)
        // Note that we purposefully also skip replying to the peer (sender) to the sender of this push yet,
        // we will do so below in any case, regardless if we are behind or not; See (4) for ACKing the peer
        for replica in push.observedSeqNrs.replicaIDs
        where replica != peerReplicaId && replica != myselfReplicaID
            && self.observedSequenceNrs[replica] < push.observedSeqNrs[replica] {
            switch replica.storage {
            case .actorID(let id):
                self.sendAckOps(receptionistID: id)

            default:
                fatalError("Only .actorID supported as replica ID, was: \(replica.storage)")
            }
        }

        // 3) Push listings for any keys that we have updated during this batch
        for key in keysToPublish {
            self.publishListings(forKey: key)
        }

        // 4) ACK that we processed the ops, if there's any more to be replayed
        //    the peer will then send us another chunk of data.
        //    IMPORTANT: We want to confirm until the _latest_ number we know about
        self.sendAckOps(receptionistID: peer.id, maybeReceptionistRef: peer)

        // 5) Since we just received ops from `peer` AND also sent it an `AckOps`,
        //    there is no need to send it another _periodic_ AckOps potentially right after.
        //    We DO want to send the Ack directly here as potentially the peer still has some more
        //    ops it might want to send, so we want to allow it to get those over to us as quickly as possible,
        //    without waiting for our Ack ticks to trigger (which could be configured pretty slow).
        let nextPeriodicAckAllowedIn: Duration = actorSystem.settings.receptionist.ackPullReplicationIntervalSlow * 2
        self.nextPeriodicAckPermittedDeadline[peer.id] = .fromNow(nextPeriodicAckAllowedIn)
    }

    /// Apply incoming operation from `peer` and update the associated applied sequenceNumber tracking
    ///
    /// - Returns: Set of keys which have been updated during this
    internal func applyIncomingOp(
        from peer: OpLogDistributedReceptionist,
        _ sequenced: OpLog<ReceptionistOp>.SequencedOp
    ) -> AnyDistributedReceptionKey {
        let operation: ReceptionistOp = sequenced.operation

        // apply operation to storage
        switch operation {
        case let .register(anyKey, identity):
            // We resolve a stub that we cannot really ever send messages to, but we can "watch" it
            let resolved: StubDistributedActor = actorSystem.resolveStub(id: identity)

            watchTermination(of: resolved)
            _ = self.storage.addRegistration(sequenced: sequenced, key: anyKey, guest: resolved)

        case let .remove(anyKey, id):
            let resolved: StubDistributedActor = actorSystem.resolveStub(id: id)

            unwatchTermination(of: resolved)
            _ = self.storage.removeRegistration(key: anyKey, guest: resolved)
        }

        // update the version up until which we updated the state
        self.appliedSequenceNrs.merge(other: VersionVector(sequenced.sequenceRange.max, at: .actorID(peer.id)))

        return operation.key
    }

    /// Acknowledge the latest applied sequence number we have from the passed in receptionist.
    ///
    /// This simultaneously acts as a "pull" conceptually, since we send an `AckOps` which confirms the latest
    /// we've applied
    /// as well as potentially causing further data to be sent.
    internal func sendAckOps(
        receptionistID: ID,
        maybeReceptionistRef: ReceptionistRef? = nil
    ) {
        assert(
            maybeReceptionistRef == nil || maybeReceptionistRef?.id == receptionistID,
            "Provided receptionistRef does NOT match passed Address, this is a bug in receptionist."
        )
        guard case .remote = receptionistID.location else {
            return  // this would mean we tried to pull from a "local" receptionist, bail out
        }

        guard self.membership.contains(receptionistID.node) else {
            // node is either not known to us yet, OR has been downed and removed
            // avoid talking to it until we see it in membership.
            return
        }

        let peerReceptionistRef: ReceptionistRef
        if let ref = maybeReceptionistRef {
            // avoiding doing a resolve if we have a real reference already
            peerReceptionistRef = ref
        } else {
            do {
                peerReceptionistRef = try ReceptionistRef.resolve(id: receptionistID, using: actorSystem)
            } catch {
                return fatalErrorBacktrace(
                    "Unable to resolve receptionist: \(receptionistID)"
                )
            }
        }

        // Get the latest seqNr of the operation that we have applied to our state
        // If we never applied anything, this automatically is `0`, and by sending an `ack(0)`,
        // we effectively initiate the "first pull"
        let latestAppliedSeqNrFromPeer: UInt64 = self.appliedSequenceNrs[.actorID(receptionistID)]

        Task { [weak self] in
            do {
                try await self?.whenLocal { myself in
                    try await peerReceptionistRef.ackOps(until: latestAppliedSeqNrFromPeer, by: myself)
                }
            } catch {
                switch error {
                case let remoteCallError as RemoteCallError where isIgnorable(remoteCallError):
                    // ignore silently; clusterAlreadyShutDown often happens during tests when we terminate systems
                    // while interacting with them. timedOut is also expected to happen sometimes.
                    ()

                default:
                    await self?.whenLocal { myself in
                        myself.log.error("Error: \(error)")
                    }
                }
            }

            func isIgnorable(_ error: RemoteCallError) -> Bool {
                switch error.underlying.error {
                case .clusterAlreadyShutDown, .timedOut:
                    return true

                default:
                    return false
                }
            }
        }
    }

    /// Listings have changed for this key, thus we need to publish them to all subscribers
    internal func publishListings(forKey key: AnyDistributedReceptionKey) {
        let subscribers: Set<DistributedListingSubscription> = self.storage.subscriptions(forKey: key)
        guard !subscribers.isEmpty else {
            return  // no subscribers for this key
        }

        self.publishListings(forKey: key, to: subscribers)
    }

    internal func publishListings(
        forKey key: AnyDistributedReceptionKey,
        to subscriptions: Set<DistributedListingSubscription>
    ) {
        let registrations: OrderedSet<VersionedRegistration> = self.storage.registrations(forKey: key)

        self.log.trace(
            "Publishing listing [\(key)]",
            metadata: [
                "receptionist/key": "\(key.id)",
                "receptionist/registrations": "\(registrations.count)",
                "receptionist/subscribers": "\(subscriptions.count)",
            ]
        )

        for subscription in subscriptions {
            for registration in registrations {
                if subscription.tryOffer(registration: registration) {
                    self.log.notice("OFFERED \(registration.actorID) TO \(subscription)")
                } else {
                    self.log.notice("DROPPED \(registration.actorID) TO \(subscription)")
                }
            }
        }
    }
}
