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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Codable ActorID

extension ActorID: Codable {

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<ActorCoding.CodingKeys> = try decoder.container(
            keyedBy: ActorCoding.CodingKeys.self
        )
        let node: Cluster.Node = try container.decode(Cluster.Node.self, forKey: ActorCoding.CodingKeys.node)
        let path: ActorPath? = try container.decodeIfPresent(ActorPath.self, forKey: ActorCoding.CodingKeys.path)
        let incarnation: UInt32 = try container.decode(UInt32.self, forKey: ActorCoding.CodingKeys.incarnation)

        self.init(remote: node, path: path, incarnation: ActorIncarnation(incarnation))

        // Decode any tags:
        if let metadataContainer = try? container.nestedContainer(
            keyedBy: ActorCoding.MetadataKeys.self,
            forKey: ActorCoding.CodingKeys.metadata
        ) {
            // tags container found, try to decode all known tags:

            let metadata: ActorMetadata = ActorMetadata()
            if let value = try? metadataContainer.decodeIfPresent(
                ActorPath.self,
                forKey: ActorCoding.MetadataKeys.path
            ) {
                metadata.path = value
            }
            if let value = try? metadataContainer.decodeIfPresent(String.self, forKey: ActorCoding.MetadataKeys.type) {
                metadata.type = .init(mangledName: value)
            }
            if let value = try? metadataContainer.decodeIfPresent(
                String.self,
                forKey: ActorCoding.MetadataKeys.wellKnown
            ) {
                metadata.wellKnown = value
            }

            if let context = decoder.actorSerializationContext {
                try context.system.settings.actorMetadata.decodeCustomMetadata(metadataContainer, self.metadata)
            }

            self.context = .init(lifecycle: nil, remoteCallInterceptor: nil, metadata: metadata)
        }
    }

    public func encode(to encoder: Encoder) throws {
        let metadataSettings: ActorIDMetadataSettings? =
            encoder.actorSerializationContext?.system.settings.actorMetadata

        var container: KeyedEncodingContainer<ActorCoding.CodingKeys> = encoder.container(
            keyedBy: ActorCoding.CodingKeys.self
        )
        try container.encode(self.node, forKey: ActorCoding.CodingKeys.node)
        try container.encode(self.path, forKey: ActorCoding.CodingKeys.path)  // remove as we remove the tree
        try container.encode(self.incarnation, forKey: ActorCoding.CodingKeys.incarnation)

        if !self.metadata.isEmpty {
            var metadataContainer: KeyedEncodingContainer<ActorCoding.MetadataKeys> = container.nestedContainer(
                keyedBy: ActorCoding.MetadataKeys.self,
                forKey: ActorCoding.CodingKeys.metadata
            )

            let keys: ActorMetadataKeys = ActorMetadataKeys.defaultInstance
            func shouldPropagate<V: Sendable & Codable>(_ key: ActorMetadataKey<V>, metadata: ActorMetadata) -> V? {
                if let metadataSettings, !metadataSettings.propagateMetadata.contains(key.id) {
                    return nil
                }
                guard let value = metadata[key.id] else {
                    return nil
                }
                guard let typedValue = value as? V else {
                    preconditionFailure("Actor metadata value does not match its registered key")
                }
                return typedValue
            }

            // Handle well known metadata types
            if let value = shouldPropagate(keys.path, metadata: self.metadata) {
                try metadataContainer.encode(value, forKey: ActorCoding.MetadataKeys.path)
            }
            if let value = shouldPropagate(keys.type, metadata: self.metadata) {
                try metadataContainer.encode(value.mangledName, forKey: ActorCoding.MetadataKeys.type)
            }
            if let value = shouldPropagate(keys.wellKnown, metadata: self.metadata) {
                try metadataContainer.encode(value, forKey: ActorCoding.MetadataKeys.wellKnown)
            }

            try metadataSettings?.encodeCustomMetadata(self.metadata, &metadataContainer)
        }
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: _ProtoActorID

extension ActorID: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoActorID

    public init(fromProto proto: _ProtoActorID, context: Serialization.Context) throws {
        let node: Cluster.Node = .init(fromProto: proto.node, context: context)

        let path: ActorPath = try ActorPath(proto.path.segments.map { try ActorPathSegment($0) })

        self.init(remote: node, path: path, incarnation: ActorIncarnation(proto.incarnation))

        // Handle well known metadata
        if !proto.metadata.isEmpty {
            let keys: ActorMetadataKeys = ActorMetadataKeys.defaultInstance

            if let data = proto.metadata[keys.type.id] {
                let manifest: Serialization.Manifest = try context.serialization.outboundManifest(String.self)
                let serialized: Serialization.Serialized = Serialization.Serialized(
                    manifest: manifest,
                    buffer: .data(data)
                )
                if let value = try? context.serialization.deserialize(as: String.self, from: serialized) {
                    self.metadata.type = .init(mangledName: value)
                }
            }

            if let data = proto.metadata[keys.wellKnown.id] {
                let manifest: Serialization.Manifest = try context.serialization.outboundManifest(String.self)
                let serialized: Serialization.Serialized = Serialization.Serialized(
                    manifest: manifest,
                    buffer: .data(data)
                )
                if let value = try? context.serialization.deserialize(as: String.self, from: serialized) {
                    self.metadata.wellKnown = value
                }
            }
        }
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoActorID {
        let metadataSettings: ActorIDMetadataSettings = context.system.settings.actorMetadata

        var proto: _ProtoActorID = _ProtoActorID()
        let node: Cluster.Node = self.node
        proto.node = node.toProto(context: context)

        proto.path.segments = self.segments.map(\.value)
        proto.incarnation = self.incarnation.value

        if !self.metadata.isEmpty {
            let keys: ActorMetadataKeys = ActorMetadataKeys.defaultInstance
            func shouldPropagate<V: Sendable & Codable>(_ key: ActorMetadataKey<V>, metadata: ActorMetadata) -> V? {
                if metadataSettings.propagateMetadata.contains(key.id) {
                    if let value = metadata[key.id] {
                        guard let typedValue = value as? V else {
                            preconditionFailure("Actor metadata value does not match its registered key")
                        }
                        return typedValue
                    }
                }
                return nil
            }

            // Handle well known metadata types
            if let value = shouldPropagate(keys.path, metadata: self.metadata) {
                let serialized: Serialization.Serialized = try context.serialization.serialize(value)
                proto.metadata[keys.path.id] = serialized.buffer.readData()
            }
            if let value = shouldPropagate(keys.type, metadata: self.metadata) {
                let serialized: Serialization.Serialized = try context.serialization.serialize(value.mangledName)
                proto.metadata[keys.type.id] = serialized.buffer.readData()
            }
            if let value = shouldPropagate(keys.wellKnown, metadata: self.metadata) {
                let serialized: Serialization.Serialized = try context.serialization.serialize(value)
                proto.metadata[keys.wellKnown.id] = serialized.buffer.readData()
            }

            // implement custom metadata transporting https://github.com/apple/swift-distributed-actors/issues/987
        }

        return proto
    }
}

extension Cluster.Node: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoClusterNode

    public init(fromProto proto: _ProtoClusterNode, context _: Serialization.Context) {
        let endpoint: Cluster.Endpoint = Cluster.Endpoint(
            protocol: proto.endpoint.protocol,
            systemName: proto.endpoint.system,
            host: proto.endpoint.hostname,
            port: Int(proto.endpoint.port)
        )

        self = .init(endpoint: endpoint, nid: Self.Identifier(proto.nid))
    }

    public func toProto(context _: Serialization.Context) -> _ProtoClusterNode {
        var proto: _ProtoClusterNode = _ProtoClusterNode()
        proto.nid = self.nid.value
        proto.endpoint.protocol = self.endpoint.protocol
        proto.endpoint.system = self.endpoint.systemName
        proto.endpoint.hostname = self.endpoint.host
        proto.endpoint.port = UInt32(self.endpoint.port)

        return proto
    }
}

extension ActorRef: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoActorID

    public init(fromProto proto: _ProtoActorID, context: Serialization.Context) throws {
        self = context.resolveActorRef(
            identifiedBy: try ActorID(fromProto: proto, context: context),
            Message.self
        )
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoActorID {
        try self.id.toProto(context: context)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: _ProtoActorPath

extension ActorPath {
    internal init(_ proto: _ProtoActorPath) throws {
        guard !proto.segments.isEmpty else {
            throw SerializationError(.emptyRepeatedField("path.segments"))
        }

        self.segments = try proto.segments.map { try ActorPathSegment($0) }
    }
}

extension _ProtoActorPath {
    internal init(_ value: ActorPath) {
        self.segments = value.segments.map(\.value)  // avoiding the mapping could be nice... store segments as strings?
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: _ProtoClusterNode

extension Cluster.Node {
    internal init(_ proto: _ProtoClusterNode) throws {
        guard proto.hasEndpoint else {
            throw SerializationError(
                .missingField("endpoint", type: String(describing: Cluster.Node.self))
            )
        }
        guard proto.nid != 0 else {
            throw SerializationError(
                .missingField("uid", type: String(describing: Cluster.Node.self))
            )
        }

        let endpoint: Cluster.Endpoint = Cluster.Endpoint(proto.endpoint)
        let nid: Self.Identifier = Self.Identifier(proto.nid)
        self.init(endpoint: endpoint, nid: nid)
    }
}

extension _ProtoClusterNode {
    internal init(_ node: Cluster.Node) {
        self.endpoint = _ProtoClusterEndpoint(node.endpoint)
        self.nid = node.nid.value
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: _ProtoClusterEndpoint

extension Cluster.Endpoint {
    internal init(_ proto: _ProtoClusterEndpoint) {
        self.protocol = proto.protocol
        self.systemName = proto.system
        self.host = proto.hostname
        self.port = Int(proto.port)
    }
}

extension _ProtoClusterEndpoint {
    internal init(_ endpoint: Cluster.Endpoint) {
        self.protocol = endpoint.protocol
        self.system = endpoint.systemName
        self.hostname = endpoint.host
        self.port = UInt32(endpoint.port)
    }
}
