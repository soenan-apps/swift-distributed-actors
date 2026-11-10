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

import CoreMetrics
import Foundation
import Logging
import struct NIO.CircularBuffer

internal final class OutboundSystemMessageRedelivery {
    internal typealias ACK = SystemMessages.ACK
    internal typealias NACK = SystemMessages.NACK
    internal typealias SequenceNr = SystemMessageEnvelope.SequenceNr

    internal enum OfferedDirective {
        /// Send the following envelope
        case send(SystemMessageEnvelope)
        /// CRITICAL ISSUE: The outgoing system message buffer has overflown and we are not able to ensure system
        /// message consistency anymore!
        case bufferOverflowMustAbortAssociation(Int)
    }

    internal enum AcknowledgeDirective {
        // ACKed and nothing else to do; nothing to re-send
        case acknowledged
        case ackWasForFutureSequenceNr(highestKnownSeqNr: SequenceNr)
    }

    internal enum NegativeAcknowledgeDirective {
        /// We got a NACK however we don't have anything to send
        /// Realistically this should not happen, as a node that sent a NACK even if it tried to send more ACKs would do
        /// so
        /// after the NACK, so it would still take effect and cause us to redeliver here; Though if for some message
        /// drop reason it were
        /// to happen, we are safe to ignore it if we have received other ACKs for pending messages already.
        case nothingToReDeliver
        case nackWasForFutureSequenceNr(highestKnownSeqNr: SequenceNr)
        /// Ensure that we'll do a redelivery soon; we could also push messages here directly but choose not to:
        /// all redelivered are done on the redelivery tick based intervals.
        case ensureRedeliveryTick(Duration)
    }

    internal enum RedeliveryTickDirective {
        /// Redeliver the following redelivery batch and schedule another redelivery tick (if more
        /// Number of elements in the exposed buffer is guaranteed to be <= `settings.redeliveryBatchSize`.
        case redeliver(CircularBuffer<TransportEnvelope>, nextTickIn: Duration)
    }

    // guaranteed to contain SystemMessageEnvelope but we also need the recipients which are in MessageEnvelope
    internal var messagesPendingAcknowledgement: NIO.CircularBuffer<TransportEnvelope> = .init(initialCapacity: 8)

    internal let metrics: ClusterSystemMetrics?

    // highest ACK we got back from the receiving end
    internal var highestAcknowledgedSeqNr: SequenceNr = 0  // 0 == no ACKs at all so far.

    // what is the highest SeqNr we have sent?
    internal var outgoingSequenceNr: SequenceNr = 0

    internal var redeliveryTicksSinceLastACK: Int = 0

    internal let settings: OutboundSystemMessageRedeliverySettings

    internal var redeliveryIntervalBackoff: ConstantBackoffStrategy

    internal init(settings: OutboundSystemMessageRedeliverySettings, metrics: ClusterSystemMetrics? = nil) {
        self.settings = settings
        self.metrics = metrics
        self.redeliveryIntervalBackoff = settings.makeRedeliveryBackoff
    }

    internal func offer(_ message: SystemMessages, recipient: ActorID) -> OfferedDirective {
        // Are we able to buffer this message?
        let nrOfMessagesPendingAcknowledgement: Int = self.messagesPendingAcknowledgement.count
        guard nrOfMessagesPendingAcknowledgement < self.settings.redeliveryBufferLimit else {
            return .bufferOverflowMustAbortAssociation(nrOfMessagesPendingAcknowledgement)
        }

        self.outgoingSequenceNr += 1
        let systemEnvelope: SystemMessageEnvelope = SystemMessageEnvelope(
            sequenceNr: self.outgoingSequenceNr, message: message
        )
        let messageEnvelope: TransportEnvelope = TransportEnvelope(
            systemMessageEnvelope: systemEnvelope, recipient: recipient
        )

        self.messagesPendingAcknowledgement.append(messageEnvelope)
        self.metrics?.systemMsgRedeliveryBuffer.record(self.messagesPendingAcknowledgement.count)

        self.outgoingSequenceNr = systemEnvelope.sequenceNr
        return .send(systemEnvelope)
    }

    internal func acknowledge(_ ack: ACK) -> AcknowledgeDirective {
        guard ack.sequenceNr <= self.outgoingSequenceNr else {
            // this is weird; we got an ACK for a higher sequence number than we ever sent to the node;
            return .ackWasForFutureSequenceNr(highestKnownSeqNr: self.outgoingSequenceNr)
        }

        let previouslyACKedToSeqNr: SequenceNr = highestAcknowledgedSeqNr
        self.highestAcknowledgedSeqNr = ack.sequenceNr

        // realistically this diff will always be in Int range:
        let nrOfMessagesAckedByThisAck: Int = Int(self.highestAcknowledgedSeqNr - previouslyACKedToSeqNr)

        self.messagesPendingAcknowledgement.removeFirst(nrOfMessagesAckedByThisAck)
        self.metrics?.systemMsgRedeliveryBuffer.record(self.messagesPendingAcknowledgement.count)

        return .acknowledged
    }

    internal func negativeAcknowledge(_ nack: NACK) -> NegativeAcknowledgeDirective {
        guard nack.sequenceNr <= self.outgoingSequenceNr else {
            // this is weird; we got an NACK for a higher sequence number than we ever sent to the node;
            return .nackWasForFutureSequenceNr(highestKnownSeqNr: self.outgoingSequenceNr)
        }

        if self.messagesPendingAcknowledgement.isEmpty {
            return .nothingToReDeliver
        }

        // a NACK has the same effect as an ACK, in the sense that it acks all messages until the "last seen" sequence
        // number.
        // we reuse the acknowledge implementation as it will do the right thing.
        let fakeAck: ACK = ACK(sequenceNr: nack.sequenceNr)
        _ = self.acknowledge(fakeAck)

        return .ensureRedeliveryTick(self.settings.redeliveryInterval)
    }

    internal func onRedeliveryTick() -> RedeliveryTickDirective {
        guard let nextTickIn = self.redeliveryIntervalBackoff.next() else {
            // technically we could avoid redelivery timers if we wanted to but it's not realistically worth it, the
            // timers will appear all the time
            fatalError(
                """
                redeliveryIntervalBackoff yielded no next redelivery time, \
                this MUST NOT happen; re-deliveries must be kept running
                """
            )
        }

        let redeliveryBatch: CircularBuffer<TransportEnvelope> = self.messagesPendingAcknowledgement.prefix(
            self.settings.redeliveryBatchSize
        )

        return .redeliver(redeliveryBatch, nextTickIn: nextTickIn)
    }
}
