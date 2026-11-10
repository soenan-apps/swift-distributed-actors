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

import Logging

/// 登録キーの識別子と対象型を保持する型消去表現。
public struct AnyReceptionKey: ReceptionKeyProtocol, Sendable, Codable, Hashable, CustomStringConvertible {
    internal enum CodingKeys: CodingKey {
        case id
        case guestTypeManifest
    }

    internal let id: String
    internal let guestType: Any.Type

    internal var asAnyKey: Self {
        self
    }

    public var description: String {
        "AnyReceptionistKey<\(reflecting: self.guestType)>(\(self.id))"
    }

    internal init<Guest>(_ key: Reception.Key<Guest>) {
        self.id = key.id
        self.guestType = Guest.self
    }

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        guard let context = decoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(decoder, Self.self)
        }

        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)

        let guestTypeManifest: Serialization.Manifest =
            try container.decode(Serialization.Manifest.self, forKey: .guestTypeManifest)
        self.guestType = try context.summonType(from: guestTypeManifest)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        if type(of: lhs) != type(of: rhs) {
            return false
        }
        if lhs.id != rhs.id {
            return false
        }
        if ObjectIdentifier(lhs.guestType) != ObjectIdentifier(rhs.guestType) {
            return false
        }
        return true
    }

    internal func resolve(system: ClusterSystem, id: ActorID) -> AddressableActorRef {
        // Since we don't have the type information here, we can't properly resolve
        // and the only safe thing to do is to return `deadLetters`.
        system.personalDeadLetters(recipient: id, type: Never.self).asAddressable
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
        hasher.combine(ObjectIdentifier(self.guestType))
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        guard let context = encoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(encoder, Self.self)
        }

        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.id, forKey: .id)
        let guestTypeManifest: Serialization.Manifest = try context.serialization.outboundManifest(self.guestType)
        try container.encode(guestTypeManifest, forKey: .guestTypeManifest)
    }
}
