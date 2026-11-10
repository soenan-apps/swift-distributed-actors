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

/// Embedded inside a `MessageEnvelope` when pushing through the transport pipeline.
///
/// Carries increasing sequence number (generation of which is done by `OutboundSystemMessageRedelivery`),
/// which is used to drive re-delivery of system messages. System messages MUST NOT be dropped, and MUST
/// be delivered in order, thus the re-delivery and local-delivery to the target actors is always done in
/// sequence and without gaps. Redelivery also survives if a connection is borked and established anew with
/// the same `Cluster.Node`.
///
/// Sequence numbers start from `1`, since zero is reserved for "no system messages were received/sent yet."
///
/// System Messages are wrapped like the following on the wire:
///
/// ```
/// +----------------------------------------------------------+
/// |  MessageEnvelope (Recipient, Baggage, ...)               |
/// |                                                          |
/// |+--------------------------------------------------------+|
/// ||  SystemMessageEnvelope (Seq. Nr)                       ||
/// ||+------------------------------------------------------+||
/// |||  System Message (Payload)                            |||
/// ||+------------------------------------------------------+||
/// |+--------------------------------------------------------+|
/// +----------------------------------------------------------+
/// ```
internal struct SystemMessageEnvelope: Equatable {
    internal typealias SequenceNr = UInt64

    internal static let metaType: MetaType<SystemMessageEnvelope> = MetaType(Self.self)
    // Actual messages start with sequence nr >= 1
    internal let sequenceNr: SequenceNr
    internal let message: SystemMessages

    internal init(sequenceNr: SequenceNr, message: SystemMessages) {
        self.sequenceNr = sequenceNr
        self.message = message
    }

    internal init(sequenceNr: Int, message: SystemMessages) {
        assert(sequenceNr > 0, "sequenceNr MUST be > 0")
        self.init(sequenceNr: SequenceNr(sequenceNr), message: message)
    }
}
