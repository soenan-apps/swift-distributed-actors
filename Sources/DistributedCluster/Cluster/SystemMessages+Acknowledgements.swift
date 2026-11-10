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

extension SystemMessages {
    /// ACKnowledgement -- sent by the receiving end for every (or coalesced) received system message.
    ///
    /// The carried `sequenceNr` indicates the "last correctly observed message"
    internal struct ACK: Equatable {
        internal let sequenceNr: SystemMessageEnvelope.SequenceNr

        internal init(sequenceNr: SystemMessageEnvelope.SequenceNr) {
            self.sequenceNr = sequenceNr
        }

        internal init(sequenceNr: Int) {
            assert(sequenceNr > 0, "sequenceNr MUST BE > 0")
            self.sequenceNr = SystemMessageEnvelope.SequenceNr(sequenceNr)
        }

        /// Coalesce ("merge") two ACKs into one cumulative ACK up until the larger sequence number carried by either of
        /// them.
        internal func coalesce(_ other: Self) -> Self {
            .init(sequenceNr: max(self.sequenceNr, other.sequenceNr))
        }
    }

    /// Negative ACKnowledgement -- sent by receiving end when it notices a gap in communication
    ///
    /// The carried `sequenceNr` indicates the "last correctly observed message" (inclusive),
    /// and is used to request all subsequent messages to be redelivered by the sender.
    internal struct NACK: Equatable {
        internal static let metaType: MetaType<NACK> = MetaType(Self.self)

        internal let sequenceNr: SystemMessageEnvelope.SequenceNr

        internal init(sequenceNr: SystemMessageEnvelope.SequenceNr) {
            self.sequenceNr = sequenceNr
        }

        internal init(sequenceNr: Int) {
            assert(sequenceNr > 0, "sequenceNr MUST be > 0")
            self.sequenceNr = SystemMessageEnvelope.SequenceNr(sequenceNr)
        }
    }
}
