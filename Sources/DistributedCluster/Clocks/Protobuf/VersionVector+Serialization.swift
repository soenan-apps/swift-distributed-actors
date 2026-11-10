// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: ReplicaID

extension ReplicaID: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoVersionReplicaID

    public init(fromProto proto: _ProtoVersionReplicaID, context: Serialization.Context) throws {
        guard let value = proto.value else {
            throw SerializationError(
                .missingField("value", type: String(describing: ReplicaID.self))
            )
        }

        switch value {
        case .actorID(let protoActorID):
            let actorID: ActorID = try ActorID(fromProto: protoActorID, context: context)
            self = .actorID(actorID)

        //        case .actorIdentity(let protoIdentity):
        //            let id = try ClusterSystem.ActorID(fromProto: protoIdentity, context: context)
        //            self = .actorIdentity(id)
        case .node(let protoNode):
            let node: Cluster.Node = Cluster.Node(fromProto: protoNode, context: context)
            self = .node(node)

        case .nodeID(let nid):
            self = .nodeID(nid)
        }
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoVersionReplicaID {
        var proto: _ProtoVersionReplicaID = _ProtoVersionReplicaID()
        switch self.storage {
        case .actorID(let actorID):
            proto.actorID = try actorID.toProto(context: context)

        //        case .actorIdentity(let actorIdentity):
        //            proto.actorIdentity = try actorIdentity.toProto(context: context)
        case .node(let node):
            proto.node = node.toProto(context: context)

        case .nodeID(let nid):
            proto.nodeID = nid.value
        }
        return proto
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: VersionVector

extension VersionVector: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoVersionVector

    public init(fromProto proto: _ProtoVersionVector, context: Serialization.Context) throws {
        // `state` defaults to [:]
        self.state.reserveCapacity(proto.state.count)

        for replicaVersion in proto.state {
            guard replicaVersion.hasReplicaID else {
                throw SerializationError(
                    .missingField("replicaID", type: String(describing: ReplicaVersion.self))
                )
            }

            let replicaID: ReplicaID = try ReplicaID(fromProto: replicaVersion.replicaID, context: context)
            state[replicaID] = replicaVersion.version
        }
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoVersionVector {
        var proto: _ProtoVersionVector = _ProtoVersionVector()

        let replicaVersions: [_ProtoReplicaVersion] = try self.state.map { replicaID, version in
            var replicaVersion: _ProtoReplicaVersion = _ProtoReplicaVersion()
            replicaVersion.replicaID = try replicaID.toProto(context: context)
            replicaVersion.version = UInt64(version)
            return replicaVersion
        }
        proto.state = replicaVersions

        return proto
    }

    /// Serialize using nodeID specifically (or crash);
    /// Used when an enclosing message already serialized the unique nodes, avoiding repeated serialization.
    public func toCompactReplicaNodeIDProto(context _: Serialization.Context) throws -> _ProtoVersionVector {
        var proto: _ProtoVersionVector = _ProtoVersionVector()

        let replicaVersions: [_ProtoReplicaVersion] = try self.state.map { replicaID, version in
            var replicaVersion: _ProtoReplicaVersion = _ProtoReplicaVersion()
            switch replicaID.storage {
            case .node(let node):
                replicaVersion.replicaID.nodeID = node.nid.value

            case .nodeID(let nid):
                replicaVersion.replicaID.nodeID = nid.value

            case .actorID:
                throw SerializationError(
                    .unableToSerialize(hint: "Can't serialize using actor address as replica id! Was: \(replicaID)")
                )
            }
            replicaVersion.version = UInt64(version)
            return replicaVersion
        }
        proto.state = replicaVersions

        return proto
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: VersionDot

extension VersionDot: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoVersionDot

    public init(fromProto proto: _ProtoVersionDot, context: Serialization.Context) throws {
        guard proto.hasReplicaID else {
            throw SerializationError(
                .missingField("replicaID", type: String(describing: VersionDot.self))
            )
        }
        self.replicaID = try ReplicaID(fromProto: proto.replicaID, context: context)
        self.version = proto.version
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoVersionDot {
        var proto: _ProtoVersionDot = _ProtoVersionDot()
        proto.replicaID = try self.replicaID.toProto(context: context)
        proto.version = UInt64(self.version)
        return proto
    }
}
