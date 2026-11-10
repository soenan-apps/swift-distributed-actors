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

import Distributed
import Logging

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct NIO.ByteBufferAllocator

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Serialization.Context

extension Serialization {
    /// A context object provided to any `Swift/Encoder`/`Swift/Decoder` used during remoteCall message serialization
    ///
    /// `Serialization.Context` may be accessed concurrently be encoders/decoders.
    public struct Context {
        /// このシリアライズ操作のロガー。
        public let log: Logger
        /// 参照の解決に使用するアクターシステム。
        public let system: ClusterSystem

        /// アクターシステムに登録されたシリアライザー。
        public var serialization: Serialization {
            self.system.serialization
        }

        /// Shared among serializers allocator for purposes of (de-)serializing messages.
        public let allocator: NIO.ByteBufferAllocator

        /// Address to be included in serialized actor refs if they are local references.
        public var localNode: Cluster.Node {
            self.system.cluster.node
        }

        internal init(log: Logger, system: ClusterSystem, allocator: NIO.ByteBufferAllocator) {
            self.log = log
            self.system = system
            self.allocator = allocator
        }

        /// Attempts to resolve ("find") an actor reference given its unique path in the current actor tree.
        /// The located actor is the _exact_ one as identified by the unique path (i.e. matching `path` and
        /// `incarnation`).
        ///
        /// If a "new" actor was started on the same `path`, its `incarnation` would be different, and thus it would not
        /// resolve using this method.
        /// This way or resolving exact references is important as otherwise one could end up sending messages to "the
        /// wrong one."
        ///
        /// Carrying `userInfo` from serialization (Coder) infrastructure may be useful to carry Transport specific
        /// information,
        /// such that a transport may _resolve_ using its own metadata.
        ///
        /// - Returns: the `ActorRef` for given actor if if exists and is alive in the tree, `nil` otherwise
        public func resolveActorRef<Message>(
            identifiedBy id: ActorID,
            _: Message.Type = Message.self,
            userInfo: [CodingUserInfoKey: Any] = [:]
        ) -> ActorRef<Message> where Message: Codable {
            let context: ResolveContext<Message> = ResolveContext<Message>(
                id: id,
                system: self.system,
                userInfo: userInfo
            )
            return self.system.resolve(context: context)
        }

        /// Similar to `resolveActorRef` but for an untyped `AddressableActorRef`.
        public func resolveAddressableActorRef(
            identifiedBy id: ActorID,
            userInfo: [CodingUserInfoKey: Any] = [:]
        ) -> AddressableActorRef {
            let context: ResolveContext<Never> = ResolveContext<Never>(id: id, system: self.system, userInfo: userInfo)
            return self.system.resolveUntyped(context: context)
        }

        /// マニフェストから登録済みの型を復元する。
        public func summonType(from manifest: Serialization.Manifest) throws -> Any.Type {
            try self.system.serialization.summonType(from: manifest)
        }

        /// Obtain a manifest for the passed `Message` type, which allows to determine which serializer should be used
        /// for the type.
        ///
        /// - SeeAlso: `Serialization.outboundManifest` for more details.
        public func outboundManifest<Message>(_ messageType: Message.Type) throws -> Serialization.Manifest {
            try self.system.serialization.outboundManifest(messageType)
        }
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Serialization.Context for Encoder & Decoder

extension CodingUserInfoKey {
    // swiftlint:disable force_unwrapping
    /// アクター参照の符号化・復元に使用するコンテキスト。
    public static let actorSerializationContext: CodingUserInfoKey = .init(rawValue: "sact_ser_context")!
    // swiftlint:enable force_unwrapping
}

extension Decoder {
    /// アクター参照の符号化・復元に使用するコンテキスト。
    public var actorSerializationContext: Serialization.Context? {
        self.userInfo[.actorSerializationContext] as? Serialization.Context
    }
}

extension JSONDecoder: CodableSerializationContext {
    /// アクター参照の符号化・復元に使用するコンテキスト。
    public var actorSerializationContext: Serialization.Context? {
        self.userInfo[.actorSerializationContext] as? Serialization.Context
    }
}

extension Encoder {
    /// アクター参照の符号化・復元に使用するコンテキスト。
    public var actorSerializationContext: Serialization.Context? {
        self.userInfo[.actorSerializationContext] as? Serialization.Context
    }
}

extension JSONEncoder: CodableSerializationContext {
    /// アクター参照の符号化・復元に使用するコンテキスト。
    public var actorSerializationContext: Serialization.Context? {
        self.userInfo[.actorSerializationContext] as? Serialization.Context
    }
}
