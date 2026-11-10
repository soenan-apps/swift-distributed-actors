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
    // Confirms that the remote peer receptionist has received Ops up until the given element,
    // allows us to push more elements
    internal final class PushOps: Receptionist.Message, @unchecked Sendable {
        // the "sender" of the push
        internal let peer: OpLogDistributedReceptionist

        // Overview of all receptionist's latest SeqNr the `peer` receptionist was aware of at time of pushing.
        // Recipient shall compare these versions and pull from appropriate nodes.
        //
        // Guaranteed to be keyed with `.actorIdentity`.
        // Yes, we're somewhat abusing the VV for our "container of sequence numbers",
        // but its merge() facility is quite handy here.
        internal let observedSeqNrs: VersionVector

        internal let sequencedOps: [OpLog<ReceptionistOp>.SequencedOp]

        internal init(
            peer: OpLogDistributedReceptionist,
            observedSeqNrs: VersionVector,
            sequencedOps: [OpLog<ReceptionistOp>.SequencedOp]
        ) {
            precondition(
                observedSeqNrs.replicaIDs.allSatisfy(\.storage.isActorID),
                """
                All observed IDs must be keyed with actor address replica IDs (of the receptionists), \
                was: \(observedSeqNrs)
                """
            )
            self.peer = peer
            self.observedSeqNrs = observedSeqNrs
            self.sequencedOps = sequencedOps
            super.init()
        }

        internal required init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<PushOpsCodingKeys> = try decoder.container(
                keyedBy: PushOpsCodingKeys.self
            )
            self.peer = try container.decode(OpLogDistributedReceptionist.self, forKey: .peer)
            self.observedSeqNrs = try container.decode(VersionVector.self, forKey: .observedSeqNrs)
            self.sequencedOps = try container.decode([OpLog<ReceptionistOp>.SequencedOp].self, forKey: .sequencedOps)
            super.init()
        }

        override internal func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<PushOpsCodingKeys> = encoder.container(
                keyedBy: PushOpsCodingKeys.self
            )
            try container.encode(self.peer, forKey: .peer)
            try container.encode(self.observedSeqNrs, forKey: .observedSeqNrs)
            try container.encode(self.sequencedOps, forKey: .sequencedOps)
        }

        // the passed ops cover the range until the following sequenceNr
        internal func findMaxSequenceNr() -> UInt64 {
            self.sequencedOps.lazy.map(\.sequenceRange.max).max() ?? 0
        }
    }

    // Confirms that the remote peer receptionist has received Ops up until the given element,
    // allows us to push more elements
    internal final class AckOps: Receptionist.Message, CustomStringConvertible, @unchecked Sendable {
        // Cumulative ACK of all ops until (and including) this one.
        //
        // If a recipient has more ops than the `confirmedUntil` confirms seeing, it shall offer
        // those to the `peer` which initiated this `ConfirmOps`
        internal let until: UInt64  // inclusive

        internal let otherObservedSeqNrs: VersionVector

        // Reference of the sender of this ConfirmOps message,
        // if more ops are available on the targets op stream, they shall be pushed to this actor.
        internal let peer: OpLogDistributedReceptionist

        internal var description: String {
            """
            Receptionist.AckOps(until: \(self.until), \
            otherObservedSeqNrs: \(self.otherObservedSeqNrs), peer: \(self.peer))
            """
        }

        internal init(appliedUntil: UInt64, observedSeqNrs: VersionVector, peer: OpLogDistributedReceptionist) {
            self.until = appliedUntil
            self.otherObservedSeqNrs = observedSeqNrs
            self.peer = peer
            super.init()
        }

        internal required init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<AckOpsCodingKeys> = try decoder.container(
                keyedBy: AckOpsCodingKeys.self
            )
            self.until = try container.decode(UInt64.self, forKey: .until)
            self.otherObservedSeqNrs = try container.decode(VersionVector.self, forKey: .otherObservedSeqNrs)
            self.peer = try container.decode(OpLogDistributedReceptionist.self, forKey: .peer)

            super.init()
        }

        override internal func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<AckOpsCodingKeys> = encoder.container(
                keyedBy: AckOpsCodingKeys.self
            )
            try container.encode(self.until, forKey: .until)
            try container.encode(self.otherObservedSeqNrs, forKey: .otherObservedSeqNrs)
            try container.encode(self.peer, forKey: .peer)
        }
    }

    internal final class PublishLocalListingsTrigger:
        Receptionist.Message,
        NotActuallyCodableMessage,
        CustomStringConvertible,
        @unchecked Sendable {
        internal var description: String {
            "Receptionist.PublishLocalListingsTrigger()"
        }

        override internal init() {
            super.init()
        }

        internal required init(from _: Decoder) throws {
            throw SerializationError(
                .nonTransportableMessage(type: "\(Self.self)")
            )
        }
    }

    internal enum PushOpsCodingKeys: CodingKey {
        case peer
        case observedSeqNrs
        case sequencedOps
    }

    internal enum AckOpsCodingKeys: CodingKey {
        case until
        case otherObservedSeqNrs
        case peer
    }
}
