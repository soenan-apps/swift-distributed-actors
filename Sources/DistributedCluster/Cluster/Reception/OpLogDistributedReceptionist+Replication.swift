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
    /// Send `AckOps` to to peers (unless prevented to by silence period because we're already
    /// conversing/streaming with one)
    internal func periodicAckTick() {
        self.log.trace("Periodic ack tick")

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
            if let periodicAckAllowedAgainDeadline = self.nextPeriodicAckPermittedDeadline[peer.id],
                periodicAckAllowedAgainDeadline.hasTimeLeft() {
                // we still cannot send acks to this peer, it is in the middle of a message exchange with us already
                continue
            }

            // the deadline is clearly overdue, so we remove the value completely to avoid them piling up
            // in there even as peers terminate
            _ = self.nextPeriodicAckPermittedDeadline.removeValue(forKey: peer.id)

            self.sendAckOps(receptionistID: peer.id, maybeReceptionistRef: peer)
        }
    }

    /// Receive an Ack and potentially continue streaming ops to peer if still pending operations available.
    internal distributed func ackOps(until: UInt64, by peer: ReceptionistRef) {
        var pendingReplayer: OpLog<ReceptionistOp>.Replayer? = self.peerReceptionistReplayers[peer]

        if pendingReplayer == nil, until == 0 {
            self.log.debug(
                "Received message from \(peer), but no replayer available, create one ad-hoc now",
                metadata: [
                    "peer": "\(peer.id.node)"
                ]
            )
            // Seems ordering became less strict here with DA unfortunately...?
            pendingReplayer = self.ops.replay(from: .beginning)
        }

        guard var replayer = pendingReplayer else {
            self.log.trace(
                "Received a confirmation until \(until) from \(peer) but no replayer available for it, ignoring",
                metadata: [
                    "receptionist/peer/confirmed": "\(until)",
                    "receptionist/peer": "\(peer.id)",
                    "replayers": "\(self.peerReceptionistReplayers)",
                ]
            )
            return
        }

        replayer.confirm(until: until)
        self.peerReceptionistReplayers[peer] = replayer

        self.replicateOpsBatch(to: peer)
    }

    internal func replicateOpsBatch(to peer: ReceptionistRef) {
        self.log.trace("Replicate ops to: \(peer.id)")
        guard peer.id != self.id else {
            self.log.trace("No need to replicate to myself: \(peer.id)")
            return  // no reason to stream updates to myself
        }

        guard let replayer = self.peerReceptionistReplayers[peer] else {
            self.log.trace(
                "Attempting to continue replay but no replayer available for it, ignoring",
                metadata: [
                    "receptionist/peer": "\(peer.id)"
                ]
            )
            return
        }

        let sequencedOps: ArraySlice<OpLog<ReceptionistOp>.SequencedOp> = replayer.nextOpsChunk()
        guard !sequencedOps.isEmpty else {
            self.log.trace(
                "No ops to replay",
                metadata: [
                    "receptionist/peer": "\(peer.id)",
                    "receptionist/ops/replay/atSeqNr": "\(replayer.atSeqNr)",
                ]
            )
            return  // nothing to stream, done
        }

        self.log.debug(
            "Streaming \(sequencedOps.count) ops: from [\(replayer.atSeqNr)]",
            metadata: [
                "receptionist/peer": "\(peer.id)",
                "receptionist/ops/replay/atSeqNr": "\(replayer.atSeqNr)",
                "receptionist/ops/maxSeqNr": "\(self.ops.maxSeqNr)",
            ]
        )

        let pushOps: PushOps = PushOps(
            peer: self,
            observedSeqNrs: self.observedSequenceNrs,
            sequencedOps: Array(sequencedOps)
        )

        self.pushBatch(pushOps, to: peer)
    }

    internal func addOperation(_ operation: ReceptionistOp) -> OpLog<ReceptionistOp>.SequencedOp {
        let sequenced: OpLog<ReceptionistOp>.SequencedOp = self.ops.add(operation)
        switch operation {
        case .register:
            actorSystem.metrics.receptionistRegistrations.increment()

        case .remove:
            actorSystem.metrics.receptionistRegistrations.decrement()
        }

        let latestSelfSeqNr: VersionVector = VersionVector(self.ops.maxSeqNr, at: .actorID(self.id))
        self.observedSequenceNrs.merge(other: latestSelfSeqNr)
        self.appliedSequenceNrs.merge(other: latestSelfSeqNr)

        actorSystem.metrics.receptionistOplogSize.record(self.ops.count)
        return sequenced
    }

    private func pushBatch(_ pushOps: PushOps, to peer: ReceptionistRef) {
        Task {
            do {
                log.debug(
                    "Push operations: \(pushOps)",
                    metadata: [
                        "receptionist/peer": "\(peer.id)"
                    ]
                )
                try await peer.pushOps(pushOps)
            } catch {
                log.error(
                    "Failed to pushOps: \(pushOps)",
                    metadata: [
                        "receptionist/peer": "\(peer.id)",
                        "error": "\(error)",
                    ]
                )
            }
        }
    }
}
