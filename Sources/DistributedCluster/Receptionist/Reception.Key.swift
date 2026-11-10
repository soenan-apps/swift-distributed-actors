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

extension Reception.Listing: Codable {
    internal enum CodingKeys: CodingKey {
        case listing
        case key
    }

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.key = try container.decode(Reception.Key<Guest>.self, forKey: .key)
        let listingDecoder: any Decoder = try container.superDecoder(forKey: .listing)
        self.underlying = try Set<AddressableActorRef>(from: listingDecoder)
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.key, forKey: .key)

        let listingEncoder: any Encoder = container.superEncoder(forKey: .listing)
        try self.underlying.encode(to: listingEncoder)
    }
}

extension Reception.Key {
    internal enum CodingKeys: CodingKey {
        case manifest
        case id
    }

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        guard let context = decoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(decoder, Reception.Listing<Guest>.self)
        }

        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        let id: String = try container.decode(String.self, forKey: .id)

        let guestManifest: Serialization.Manifest = try container.decode(Serialization.Manifest.self, forKey: .manifest)
        let guestType: Any.Type = try context.summonType(from: guestManifest)
        guard guestType is Guest.Type else {
            throw SerializationError(
                .unableToDeserialize(
                    hint: "manifest type results in [\(guestType)] type, which is NOT \(Guest.self)"
                )
            )
        }

        self.init(Guest.self, id: id)
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        guard let context: Serialization.Context = encoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(encoder, Reception.Listing<Guest>.self)
        }
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        let manifest: Serialization.Manifest = try context.outboundManifest(Guest.self)

        try container.encode(manifest, forKey: .manifest)
        try container.encode(self.id, forKey: .id)
    }
}
