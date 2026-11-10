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

/// Each association has one inbound system message queue.
@usableFromInline
internal class InboundSystemMessages {
    internal typealias ACK = SystemMessages.ACK
    internal typealias NACK = SystemMessages.NACK
    internal typealias SequenceNr = SystemMessageEnvelope.SequenceNr

    internal enum InboundSystemMessageArrivalDirective: Equatable {
        case accept(ACK)
        case acceptRedelivery(ACK)
        case gapDetectedRequestRedelivery(NACK)
    }

    /// we expect the first incoming message to be of sequence nr == 1.
    internal var expectedSequenceNr: SequenceNr = 1

    internal let settings: InboundSystemMessageRedeliverySettings

    internal init(settings: InboundSystemMessageRedeliverySettings) {
        self.settings = settings
    }

    internal func onDelivery(_ envelope: SystemMessageEnvelope) -> InboundSystemMessageArrivalDirective {
        if envelope.sequenceNr == self.expectedSequenceNr {
            // good, just what we expected!
            return self.accept()
        }
        if envelope.sequenceNr < self.expectedSequenceNr {
            // neutral, we have already seen this message; it seems to have been re-delivered again
            // perhaps the other side did not receive our previous Ack?
            // Let's let it know again up-until which seqNr we know about already:
            return .acceptRedelivery(ACK(sequenceNr: self.expectedSequenceNr - 1))
        }
        assert(envelope.sequenceNr > self.expectedSequenceNr)
        // bad, we're missing a message (!)
        return .gapDetectedRequestRedelivery(NACK(sequenceNr: self.expectedSequenceNr - 1))
    }

    private func accept() -> InboundSystemMessageArrivalDirective {
        let ack: ACK = ACK(sequenceNr: expectedSequenceNr)
        self.expectedSequenceNr += 1
        return .accept(ack)
    }
}
