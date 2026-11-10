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

import CDistributedActorsMailbox
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf

extension Serialization.Settings {
    /// Register a `Serialization.Manifest` for the given `Codable` type and `Serializer`.
    ///
    /// If no `serializer` is selected, it will default to the the `settings.defaultCodableSerializerID`.
    /// If you aim to change the default, be sure to do so before registering any manifests as they pick up
    /// the default serializer ID at time of registration.
    ///
    /// This can be used to "force" a specific serializer be used for a message type,
    /// regardless if it is codable or not.
    @discardableResult
    public mutating func register<Message: Codable>(
        _ type: Message.Type,
        hint hintOverride: String? = nil,
        serializerID overrideSerializerID: Serialization.SerializerID? = nil,
        alsoRegisterActorRef: Bool = true
    ) -> Serialization.Manifest {
        let hint: String = hintOverride ?? Serialization.getTypeHint(type)

        if overrideSerializerID == Serialization.SerializerID.protobufRepresentable {
            precondition(
                type is AnyProtobufRepresentable.Type || type is SwiftProtobuf.Message.Type,
                """
                Attempted to register \(String(reflecting: type)) as \
                serializable using \(reflecting: overrideSerializerID), \
                yet the type does NOT conform to ProtobufRepresentable or SwiftProtobuf.Message
                """
            )
        }

        let serializerID: Serialization.SerializerID
        if let overrideSerializerID = overrideSerializerID {
            serializerID = overrideSerializerID
        } else if let serializationRepresentableType = Message.self as? SerializationRepresentable.Type {
            serializerID = serializationRepresentableType.defaultSerializerID ?? self.defaultSerializerID
        } else {
            serializerID = self.defaultSerializerID
        }

        let manifest: Serialization.Manifest = Serialization.Manifest(serializerID: serializerID, hint: hint)

        self.typeToManifestRegistry[.init(type)] = manifest
        self.manifest2TypeRegistry[manifest] = type

        if alsoRegisterActorRef {
            _ = self.register(ActorRef<Message>.self, alsoRegisterActorRef: false)
            _ = self.register(ActorRef<Result<Message, ErrorEnvelope>>.self, alsoRegisterActorRef: false)
        }

        return manifest
    }

    /// Stores additional manifest that is known may be incoming, yet resolves to a specific type.
    ///
    /// This manifest will NOT be used when _sending_ messages of the `Message` type.
    @discardableResult
    public mutating func registerInbound<Message: Codable>(
        _ type: Message.Type,
        hint hintOverride: String? = nil,
        serializerID overrideSerializerID: Serialization.SerializerID? = nil
    ) -> Serialization.Manifest {
        let hint: String = hintOverride ?? _mangledTypeName(type) ?? _typeName(type)
        let serializerID: Serialization.SerializerID = overrideSerializerID ?? self.defaultSerializerID

        let manifest: Serialization.Manifest = Serialization.Manifest(serializerID: serializerID, hint: hint)

        self.manifest2TypeRegistry[manifest] = type

        return manifest
    }
}

extension Serialization.Settings {
    /// Register a specialized serializer for a specific `Serialization.Manifest`.
    internal mutating func registerSpecializedSerializer<Message>(
        _ type: Message.Type,
        serializerID: Serialization.SerializerID,
        hint hintOverride: String? = nil,
        makeSerializer: @escaping (NIO.ByteBufferAllocator) -> Serializer<Message>
    ) {
        precondition(
            serializerID == .specializedWithTypeHint || serializerID > 16,
            "Specialized serializerID MUST exactly `1` or be `> 16`, since IDs until 16 are reserved "
                + "for general purpose serializers"
        )
        let hint: String = hintOverride ?? _mangledTypeName(type) ?? _typeName(type)
        let manifest: Serialization.Manifest = Serialization.Manifest(serializerID: serializerID, hint: hint)

        self.specializedSerializerMakers[manifest] = { allocator in
            makeSerializer(allocator).asAnySerializer
        }
    }

    /// 専用シリアライザーを取得するか、型のマニフェストを登録する。
    public mutating func getSpecializedOrRegisterManifest<Message: Codable>(
        _ type: Message.Type,
        serializerID: Serialization.SerializerID
    ) -> Serialization.Manifest {
        self.typeToManifestRegistry[.init(type)] ?? self.register(type, serializerID: serializerID)
    }
}
