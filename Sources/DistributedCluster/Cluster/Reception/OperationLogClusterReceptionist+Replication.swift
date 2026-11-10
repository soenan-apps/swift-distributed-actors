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

import CoreMetrics
import Logging

extension OperationLogClusterReceptionist {
    /// Received a push of ops; apply them to the local view of the key space (storage).
    ///
    /// The incoming ops will be until some max SeqNr, once we have applied them all,
    /// we send back an `ack(maxSeqNr)` to both confirm the receipt, as well as potentially trigger
    /// more ops being delivered
    internal func receiveOps(_ context: ActorContext<Message>, push: PushOps) {
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

        context.log.trace(
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
        var keysToPublish: Set<AnyReceptionKey> = []
        for operation in opsToApply {
            keysToPublish.insert(self.applyIncomingOp(context, from: peer, operation))
        }

        context.log.trace("Keys to publish: \(keysToPublish)")

        // 1.2) update our observed version of `pushed.peer` to the incoming
        self.observedSequenceNrs.merge(other: push.observedSeqNrs)
        self.appliedSequenceNrs.merge(other: .init(push.findMaxSequenceNr(), at: peerReplicaId))

        // 2) check for all peers if we are "behind", and should pull information from them
        //    if this message indicated "end" of the push, then we assume we are up to date with it
        //    and will only pull again from it on the SlowACK
        let myselfReplicaID: ReplicaID = .actorID(context.myself.id)
        // Note that we purposefully also skip replying to the peer (sender) to the sender of this push yet,
        // we will do so below in any case, regardless if we are behind or not; See (4) for ACKing the peer
        for replica in push.observedSeqNrs.replicaIDs
        where replica != peerReplicaId && replica != myselfReplicaID
            && self.observedSequenceNrs[replica] < push.observedSeqNrs[replica] {
            switch replica.storage {
            case .actorID(let address):
                self.sendAckOps(context, receptionistAddress: address)

            default:
                fatalError("Only .actorID supported as replica ID")
            }
        }

        // 3) Push listings for any keys that we have updated during this batch
        for key in keysToPublish {
            self.publishListings(context, forKey: key)
        }

        // 4) ACK that we processed the ops, if there's any more to be replayed
        //    the peer will then send us another chunk of data.
        //    IMPORTANT: We want to confirm until the _latest_ number we know about
        self.sendAckOps(context, receptionistAddress: peer.id, maybeReceptionistRef: peer)

        // 5) Since we just received ops from `peer` AND also sent it an `AckOps`,
        //    there is no need to send it another _periodic_ AckOps potentially right after.
        //    We DO want to send the Ack directly here as potentially the peer still has some more
        //    ops it might want to send, so we want to allow it to get those over to us as quickly as possible,
        //    without waiting for our Ack ticks to trigger (which could be configured pretty slow).
        let nextPeriodicAckAllowedIn: Duration = context.system.settings.receptionist.ackPullReplicationIntervalSlow * 2
        self.nextPeriodicAckPermittedDeadline[peer] = .fromNow(nextPeriodicAckAllowedIn)
    }

    /// Apply incoming operation from `peer` and update the associated applied sequenceNumber tracking
    ///
    /// - Returns: Set of keys which have been updated during this
    internal func applyIncomingOp(
        _ context: ActorContext<Message>,
        from peer: ActorRef<Message>,
        _ sequenced: OpLog<ReceptionistOp>.SequencedOp
    ) -> AnyReceptionKey {
        let operation: ReceptionistOp = sequenced.operation

        // apply operation to storage
        switch operation {
        case let .register(key, id):
            let resolved: AddressableActorRef = context.system.resolveUntyped(
                context: .init(id: id, system: context.system)
            )
            context.watch(resolved)
            if self.storage.addRegistration(key: key, ref: resolved) {
                self.instrumentation.actorRegistered(key: key, id: id)
            }

        case let .remove(key, id):
            let resolved: AddressableActorRef = context.system.resolveUntyped(
                context: .init(id: id, system: context.system)
            )
            context.unwatch(resolved)
            if !self.storage.removeRegistration(key: key, ref: resolved).isEmpty {
                self.instrumentation.actorRemoved(key: key, id: id)
            }
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
        _ context: ActorContext<Message>,
        receptionistAddress: ActorID,
        maybeReceptionistRef: ReceptionistRef? = nil
    ) {
        assert(
            maybeReceptionistRef == nil || maybeReceptionistRef?.id == receptionistAddress,
            "Provided receptionistRef does NOT match passed Address, this is a bug in receptionist."
        )
        guard case .remote = receptionistAddress.location else {
            return  // this would mean we tried to pull from a "local" receptionist, bail out
        }

        guard self.membership.contains(receptionistAddress.node) else {
            // node is either not known to us yet, OR has been downed and removed
            // avoid talking to it until we see it in membership.
            return
        }

        let peerReceptionistRef: ReceptionistRef
        if let ref = maybeReceptionistRef {
            peerReceptionistRef = ref  // allows avoiding to have to perform a resolve here
        } else {
            peerReceptionistRef = context.system.resolve(
                context: .init(id: receptionistAddress, system: context.system)
            )
        }

        // Get the latest seqNr of the operation that we have applied to our state
        // If we never applied anything, this automatically is `0`, and by sending an `ack(0)`,
        // we effectively initiate the "first pull"
        let latestAppliedSeqNrFromPeer: UInt64 = self.appliedSequenceNrs[.actorID(receptionistAddress)]

        let ack: AckOps = AckOps(
            appliedUntil: latestAppliedSeqNrFromPeer,
            observedSeqNrs: self.observedSequenceNrs,
            peer: context.myself
        )

        tracelog(
            context,
            .push(destination: peerReceptionistRef),
            message: ack
        )
        peerReceptionistRef.tell(ack)
    }

    /// Listings have changed for this key, thus we need to publish them to all subscribers
    internal func publishListings(_ context: ActorContext<Message>, forKey key: AnyReceptionKey) {
        let subscribers: Set<AnySubscribe> = self.storage.subscriptions(forKey: key)
        guard !subscribers.isEmpty else {
            return  // no subscribers for this key
        }

        self.publishListings(context, forKey: key, to: subscribers)
    }

    internal func publishListings(
        _ context: ActorContext<Message>,
        forKey key: AnyReceptionKey,
        to subscribers: Set<AnySubscribe>
    ) {
        let registrations: Set<AddressableActorRef> = self.storage.registrations(forKey: key)

        context.log.trace(
            "Publishing listing [\(key)]",
            metadata: [
                "receptionist/key": "\(key.id)",
                "receptionist/registrations": "\(registrations.count)",
                "receptionist/subscribers": "\(subscribers.count)",
            ]
        )

        for subscriber: AnySubscribe in subscribers {
            subscriber.reply(registrations)
        }
    }

    /// Send `AckOps` to to peers (unless prevented to by silence period because we're already
    /// conversing/streaming with one)
    internal func onPeriodicAckTick(_ context: ActorContext<Message>) {
        for peer in self.peerReceptionistReplayers.keys {
            // In order to avoid sending spurious acks which would cause the peer to start delivering
            // from the acknowledged `until`,
            // e.g. while it is still in the middle of sending us more ops, we avoid sending more acks
            // earlier than a regular "tick"
            // from the point in time we last received ops from this peer. In practice this means:
            // - if we are in the middle of an ack/ops exchange between us and the peer, we will not send
            // another ack here -- an eager one (not timer based) was already sent
            //   - if the eager ack would has been lost, this timer will soon enough trigger again, and
            // we'll deliver the ack this way
            // - if we are NOT in the middle of receiving ops, we share our observed versions and ack as
            // means of spreading information about the seen SeqNrs
            //   - this may cause the other peer to pull (ack) from any other peer receptionist, if it
            // notices it is "behind" with regards to any of them.
            if let periodicAckAllowedAgainDeadline = self.nextPeriodicAckPermittedDeadline[peer],
                periodicAckAllowedAgainDeadline.hasTimeLeft() {
                // we still cannot send acks to this peer, it is in the middle of a message exchange with us already
                continue
            }

            // the deadline is clearly overdue, so we remove the value completely to avoid them piling up
            // in there even as peers terminate
            _ = self.nextPeriodicAckPermittedDeadline.removeValue(forKey: peer)

            self.sendAckOps(context, receptionistAddress: peer.id, maybeReceptionistRef: peer)
        }
    }

    /// Receive an Ack and potentially continue streaming ops to peer if still pending operations available.
    internal func receiveAckOps(
        _ context: ActorContext<Message>,
        until: UInt64,
        by peer: ActorRef<OperationLogClusterReceptionist.Message>
    ) {
        guard var replayer = self.peerReceptionistReplayers[peer] else {
            context.log.trace(
                "Received a confirmation until \(until) from \(peer) but no replayer available for it, ignoring"
            )
            return
        }

        replayer.confirm(until: until)
        self.peerReceptionistReplayers[peer] = replayer

        self.replicateOpsBatch(context, to: peer)
    }

    internal func replicateOpsBatch(_ context: ActorContext<Message>, to peer: ActorRef<Receptionist.Message>) {
        guard peer.id != context.id else {
            return  // no reason to stream updates to myself
        }

        guard let replayer = self.peerReceptionistReplayers[peer] else {
            context.log.trace("Attempting to continue replay for \(peer) but no replayer available for it, ignoring")
            return
        }

        let sequencedOps: ArraySlice<OpLog<ReceptionistOp>.SequencedOp> = replayer.nextOpsChunk()
        guard !sequencedOps.isEmpty else {
            return  // nothing to stream, done
        }

        context.log.debug(
            "Streaming \(sequencedOps.count) ops: from [\(replayer.atSeqNr)]",
            metadata: [
                "receptionist/peer": "\(peer.id)",
                "receptionist/ops/replay/atSeqNr": "\(replayer.atSeqNr)",
                "receptionist/ops/maxSeqNr": "\(self.ops.maxSeqNr)",
            ]
        )

        let pushOps: PushOps = PushOps(
            peer: context.myself,
            observedSeqNrs: self.observedSequenceNrs,
            sequencedOps: Array(sequencedOps)
        )
        self.tracelog(
            context,
            .push(destination: peer),
            message: pushOps
        )

        // hack in order ro override the Message.self being used to find the serializer
        switch peer.personality {
        case .remote(let remote):
            remote.sendUserMessage(pushOps)

        default:
            fatalError("Remote receptionists MUST be of .remote personality, was: \(peer.personality), \(peer.id)")
        }
    }

    internal func addOperation(_ context: ActorContext<Message>, _ operation: ReceptionistOp) {
        self.ops.add(operation)
        switch operation {
        case .register:
            context.system.metrics.receptionistRegistrations.increment()

        case .remove:
            context.system.metrics.receptionistRegistrations.decrement()
        }

        let latestSelfSeqNr: VersionVector = VersionVector(self.ops.maxSeqNr, at: .actorID(context.myself.id))
        self.observedSequenceNrs.merge(other: latestSelfSeqNr)
        self.appliedSequenceNrs.merge(other: latestSelfSeqNr)

        context.system.metrics.receptionistOplogSize.record(self.ops.count)
    }
}
