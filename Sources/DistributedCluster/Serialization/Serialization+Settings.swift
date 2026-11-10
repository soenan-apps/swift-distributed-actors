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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Serialization Settings

extension Serialization {
    /// メッセージ型の登録とワイヤー形式の選択を設定する。
    public struct Settings {
        /// 既定の設定。
        public static var `default`: Self {
            .init()
        }

        /// When `true`, all messages are allowed to be sent (serialized, and deserialized) regardless if they were
        /// registered with serialization or not. While this setting is true, the system will log a warning about each
        /// message type when it is first encountered during the systems operation, and it will suggest registering that
        /// type.
        /// This way one can use this setting in local debugging and quick iteration, and then easily register all
        /// necessary types
        /// when deploying to production.
        ///
        /// - Warning: Do not set this value to true in production deployments, as it could be used send and deserialize
        /// any codable type
        ///   and the serialization infrastructure would attempt deserializing it, potentially opening up for security
        ///   risks.
        public var insecureSerializeNotRegisteredMessages: Bool = _isDebugAssertConfiguration()

        /// Configures which `Codable` serializer (`Encoder` / `Decoder` pair) should be used whenever a
        /// a message is sent however the type does not have a specific serializer requirement configured (via
        /// `register` calls).
        ///
        ///
        /// - Note: Affects only _outbound_ messages which are `Codable`.
        public var defaultSerializerID: Serialization.SerializerID = .foundationJSON

        /// `Cluster.Node` to be included in actor addresses when serializing them.
        /// By default this should be equal to the exposed node of the actor system.
        ///
        /// If clustering is not configured on this node, this value SHOULD be `nil`,
        /// as it is not useful to render any address for actors which shall never be reached remotely.
        ///
        /// This is set automatically when modifying the systems cluster settings.
        internal var localNode: Cluster.Node =
            .init(
                systemName: "<mock-value-will-be-replaced-during-system-start>",
                host: "127.0.0.1",
                port: 7_337,
                nid: Cluster.Node.Identifier(0)
            )

        /// Applied before automatically selecting a serializer based on manifest.
        /// Allows to deserialize incoming messages when "the same" message is now represented on this system
        /// differently.
        ///
        /// Use cases:
        /// - deserialize messages "the old way" while they are incoming, and serialize them "the new way" when sending
        /// them.
        internal var inboundSerializerManifestMappings: [Serialization.Manifest: Serialization.Manifest] = [:]

        /// Factories for specialized (e.g. specific `Serialization.SerializerID -> T`) serializers,
        /// which unlike Codable serializers can not be created ad-hoc for a given T.
        ///
        /// E.g. protocol buffer based serializers.
        internal var specializedSerializerMakers: [
            Serialization.Manifest: (NIO.ByteBufferAllocator) -> AnySerializer
        ] = [:]

        internal var typeToManifestRegistry: [SerializerTypeKey: Serialization.Manifest] = [:]
        internal var manifest2TypeRegistry: [Serialization.Manifest: Any.Type] = [:]

        /// Allocator to be used by the serialization infrastructure.
        ///
        /// It will be shared by all serialization/deserialization invocations.
        public var allocator: ByteBufferAllocator = NIO.ByteBufferAllocator()
    }
}
