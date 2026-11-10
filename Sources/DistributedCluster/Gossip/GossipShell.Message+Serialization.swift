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

import struct Foundation.Data

extension GossipShell.Message: Codable {
    internal enum DiscriminatorKeys: String, Codable {
        case gossip = "gossip"
    }

    internal enum CodingKeys: String, CodingKey {
        case ackRef = "ackRef"
        case discriminator = "_case"
        case gossipIdentifier = "gossip_identifier"
        case gossipIdentifierManifest = "gossip_identifier_manifest"
        case gossipPayload = "gossip_payload"
        case gossipPayloadManifest = "gossip_payload_manifest"
        case origin = "origin"
    }

    internal init(from decoder: Decoder) throws {
        guard let context: Serialization.Context = decoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(decoder, Self.self)
        }

        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: .discriminator) {
        case .gossip:
            let identifierManifest: Serialization.Manifest = try container.decode(
                Serialization.Manifest.self,
                forKey: .gossipIdentifierManifest
            )
            let identifierPayload: Data = try container.decode(Data.self, forKey: .gossipIdentifier)
            guard
                let identifier = try context.serialization.deserializeAny(
                    from: .data(identifierPayload),
                    using: identifierManifest
                ) as? GossipIdentifier
            else {
                fatalError("Cannot cast decoded identifier to GossipIdentifier")
            }

            let originAddress: ActorID = try container.decode(ActorID.self, forKey: .origin)
            let origin: ActorRef<Self> = context.resolveActorRef(identifiedBy: originAddress, Self.self)

            // sometimes we could encode raw and not via the Data -- think about it and fix it
            let payloadManifest: Serialization.Manifest = try container.decode(
                Serialization.Manifest.self,
                forKey: .gossipPayloadManifest
            )
            let payloadPayload: Data = try container.decode(Data.self, forKey: .gossipPayload)
            let payload: Gossip = try context.serialization.deserialize(
                as: Gossip.self,
                from: .data(payloadPayload),
                using: payloadManifest
            )

            let ackRefAddress: ActorID? = try container.decodeIfPresent(ActorID.self, forKey: .ackRef)
            let ackRef: ActorRef<Acknowledgement>? = ackRefAddress.map { address in
                context.resolveActorRef(identifiedBy: address, Acknowledgement.self)
            }

            self = .gossip(identity: identifier, origin: origin, payload, ackRef: ackRef)
        }
    }

    internal func encode(to encoder: Encoder) throws {
        guard let context: Serialization.Context = encoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(encoder, self)
        }

        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .gossip(identifier, origin, payload, ackRef):
            try container.encode(DiscriminatorKeys.gossip, forKey: .discriminator)

            let serializedIdentifier: Serialization.Serialized = try context.serialization.serialize(identifier)
            try container.encode(serializedIdentifier.manifest, forKey: .gossipIdentifierManifest)
            try container.encode(serializedIdentifier.buffer.readData(), forKey: .gossipIdentifier)

            try container.encode(origin.id, forKey: .origin)

            let serializedPayload: Serialization.Serialized = try context.serialization.serialize(payload)
            try container.encode(serializedPayload.manifest, forKey: .gossipPayloadManifest)
            try container.encode(serializedPayload.buffer.readData(), forKey: .gossipPayload)

            try container.encodeIfPresent(ackRef?.id, forKey: .ackRef)

        default:
            throw SerializationError(.unableToSerialize(hint: "\(reflecting: Self.self)"))
        }
    }
}
