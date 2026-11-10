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

import Foundation  // for Codable
import NIO
import NIOFoundationCompat

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Codable ActorRef

extension ActorRef {

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        let id: ActorID = try container.decode(ActorID.self)

        guard let context = decoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(decoder, ActorRef<Message>.self)
        }

        // Important: We need to carry the `userInfo` as it may contain information set by a Transport that it needs in
        // order to resolve a ref. This allows the transport to resolve any actor ref, even if they are contained in
        // user-messages.
        self = context.resolveActorRef(identifiedBy: id, userInfo: decoder.userInfo)
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        var container: any SingleValueEncodingContainer = encoder.singleValueContainer()
        try container.encode(self.id)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Codable ReceivesMessages

extension ReceivesMessages {

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        let id: ActorID = try container.decode(ActorID.self)

        guard let context = decoder.actorSerializationContext else {
            fatalError("Can not resolve actor refs without CodingUserInfoKey.actorSerializationContext set!")
        }

        let resolved: ActorRef<Self.Message> = context.resolveActorRef(identifiedBy: id)
        guard let typed = resolved as? Self else {
            throw DecodingError.typeMismatch(
                Self.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Resolved reference has a different type")
            )
        }
        self = typed
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        var container: any SingleValueEncodingContainer = encoder.singleValueContainer()
        switch self {
        case let ref as ActorRef<Message>:
            try container.encode(ref.id)

        default:
            fatalError("Can not serialize non-ActorRef ReceivesMessages! Was: \(self)")
        }
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Codable ReceivesSystemMessages

/// Warning: presence of this extension and `ReceivesSystemMessages` being `Codable` does not actually enable users
/// to embed and use `ReceivesSystemMessages` inside codable messages: it would fail synthesizing the codable code for
/// this type automatically, since users can not access the type at all.
/// The `ReceivesSystemMessagesDecoder` however does enable this library itself to embed and use this type in Codable
/// messages, if the need were to arise.
extension ReceivesSystemMessages {

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        guard let resolved = try ReceivesSystemMessagesDecoder.decode(from: decoder) as? Self else {
            throw DecodingError.typeMismatch(
                Self.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Resolved reference has a different type")
            )
        }
        self = resolved
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        var container: any SingleValueEncodingContainer = encoder.singleValueContainer()
        traceLog_Serialization(
            "encode \(self.id) WITH address",
            file: #fileID,
            line: #line
        )
        try container.encode(self.id)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Codable ActorPath

// Customize coding to avoid nesting as {"value": "..."}
extension ActorPath: Codable {

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<ActorCoding.CodingKeys> =
            try decoder.container(keyedBy: ActorCoding.CodingKeys.self)
        let segments: [ActorPathSegment] =
            try container.decode([ActorPathSegment].self, forKey: ActorCoding.CodingKeys.path)
        self = try ActorPath(segments)
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<ActorCoding.CodingKeys> =
            encoder.container(keyedBy: ActorCoding.CodingKeys.self)
        try container.encode(self.segments, forKey: ActorCoding.CodingKeys.path)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Codable ActorPath elements

// Customize coding to avoid nesting as {"value": "..."}
extension ActorPathSegment: Codable {

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        do {
            let container: any SingleValueDecodingContainer = try decoder.singleValueContainer()
            let value: String = try container.decodeNonEmpty(String.self, hint: "ActorPathSegment")

            try self.init(value)
        } catch {
            throw error
        }
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        var container: any SingleValueEncodingContainer = encoder.singleValueContainer()
        try container.encode(self.value)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Codable Incarnation

// Customize coding to avoid nesting as {"value": "..."}
extension ActorIncarnation: Codable {

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        do {
            let container: any SingleValueDecodingContainer = try decoder.singleValueContainer()
            let value: Int = try container.decode(Int.self)

            self.init(value)
        } catch {
            throw error
        }
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        var container: any SingleValueEncodingContainer = encoder.singleValueContainer()
        try container.encode(self.value)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Codable Node Address

extension Cluster.Endpoint: Codable {

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        var container: any UnkeyedDecodingContainer = try decoder.unkeyedContainer()
        self.protocol = try container.decode(String.self)
        self.systemName = try container.decode(String.self)
        self.host = try container.decode(String.self)
        self.port = try container.decode(Int.self)
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        var container: any UnkeyedEncodingContainer = encoder.unkeyedContainer()
        try container.encode(self.protocol)
        // ://
        try container.encode(self.systemName)
        // @
        try container.encode(self.host)
        // :
        try container.encode(self.port)
    }
}

extension Cluster.Node: Codable {

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        var container: any UnkeyedDecodingContainer = try decoder.unkeyedContainer()
        let `protocol`: String = try container.decode(String.self)
        let systemName: String = try container.decode(String.self)
        let host: String = try container.decode(String.self)
        let port: Int = try container.decode(Int.self)
        self.endpoint = Cluster.Endpoint(protocol: `protocol`, systemName: systemName, host: host, port: port)
        self.nid = try Self.Identifier(container.decode(UInt64.self))
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        var container: any UnkeyedEncodingContainer = encoder.unkeyedContainer()
        try container.encode(self.endpoint.protocol)
        // ://
        try container.encode(self.endpoint.systemName)
        // @
        try container.encode(self.endpoint.host)
        // :
        try container.encode(self.endpoint.port)
        // #
        try container.encode(self.nid.value)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Convenience coding functions

extension SingleValueDecodingContainer {
    internal func decodeNonEmpty(_ type: String.Type, hint: String) throws -> String {
        let value: String = try self.decode(type)
        if value.isEmpty {
            throw DecodingError.dataCorruptedError(
                in: self,
                debugDescription: "Cannot initialize [\(hint)] from an empty string!"
            )
        }
        return value
    }
}

extension UnkeyedDecodingContainer {
    internal mutating func decodeNonEmpty(_ type: String.Type, hint: String) throws -> String {
        let value: String = try self.decode(type)
        if value.isEmpty {
            throw DecodingError.dataCorruptedError(
                in: self,
                debugDescription: "Cannot initialize [\(hint)] from an empty string!"
            )
        }
        return value
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Codable SystemMessage

extension SystemMessages: Codable {
    internal enum CodingKeys: CodingKey {
        case type

        case watchee
        case watcher

        case existenceConfirmed
        case idTerminated
        case ref
    }

    internal enum Types {
        internal static let watch: Int = 0
        internal static let terminated: Int = 1
    }

    /// ワイヤー表現から値を復元する。
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Int.self, forKey: CodingKeys.type) {
        case Types.watch:
            guard let context = decoder.actorSerializationContext else {
                throw SerializationError.missingSerializationContext(decoder, Self.self)
            }
            let watcheeID: ActorID = try container.decode(ActorID.self, forKey: CodingKeys.watchee)
            let watcherID: ActorID = try container.decode(ActorID.self, forKey: CodingKeys.watcher)
            let watchee: AddressableActorRef = context.resolveAddressableActorRef(identifiedBy: watcheeID)
            let watcher: AddressableActorRef = context.resolveAddressableActorRef(identifiedBy: watcherID)
            self = .watch(watchee: watchee, watcher: watcher)

        case Types.terminated:
            guard let context = decoder.actorSerializationContext else {
                throw SerializationError.missingSerializationContext(decoder, Self.self)
            }
            let id: ActorID = try container.decode(ActorID.self, forKey: CodingKeys.ref)
            let ref: AddressableActorRef = context.resolveAddressableActorRef(identifiedBy: id)
            let existenceConfirmed: Bool = try container.decode(Bool.self, forKey: CodingKeys.existenceConfirmed)
            let idTerminated: Bool = try container.decode(Bool.self, forKey: CodingKeys.idTerminated)
            self = .terminated(ref: ref, existenceConfirmed: existenceConfirmed, idTerminated: idTerminated)

        case let type:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Cannot decode system-message type \(type)"
            )
        }
    }

    /// 指定したエンコーダーへワイヤー表現を書き出す。
    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .watch(watchee, watcher):
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(Types.watch, forKey: CodingKeys.type)

            try container.encode(watchee.id, forKey: CodingKeys.watchee)
            try container.encode(watcher.id, forKey: CodingKeys.watcher)

        case let .terminated(ref, existenceConfirmed, idTerminated):
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Types.terminated, forKey: CodingKeys.type)

            try container.encode(ref.id, forKey: CodingKeys.ref)
            try container.encode(existenceConfirmed, forKey: CodingKeys.existenceConfirmed)
            try container.encode(idTerminated, forKey: CodingKeys.idTerminated)

        default:
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: encoder.codingPath, debugDescription: "Not serializable: \(self)")
            )
        }
    }
}
