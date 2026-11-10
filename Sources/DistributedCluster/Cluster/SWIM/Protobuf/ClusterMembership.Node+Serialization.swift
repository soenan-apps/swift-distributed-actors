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

import ClusterMembership
import Foundation
import SWIM

extension ClusterMembership.Node: @retroactive Decodable, @retroactive Encodable, ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoClusterNode

    public init(fromProto proto: ProtobufRepresentation, context _: Serialization.Context) throws {
        guard proto.hasEndpoint else {
            throw SerializationError(.missingField("endpoint", type: String(describing: Cluster.Endpoint.self)))
        }
        let protoNode: _ProtoClusterEndpoint = proto.endpoint
        let `protocol`: String = protoNode.protocol
        let name: String?
        if !protoNode.system.isEmpty {
            name = protoNode.system
        } else {
            name = nil
        }
        let host: String = protoNode.hostname
        let port: Int = Int(protoNode.port)

        let uid: UInt64 = proto.nid
        self.init(protocol: `protocol`, name: name, host: host, port: port, uid: uid)
    }

    public func toProto(context _: Serialization.Context) -> ProtobufRepresentation {
        var proto: ProtobufRepresentation = ProtobufRepresentation()
        var protoEndpoint: _ProtoClusterEndpoint = _ProtoClusterEndpoint()
        protoEndpoint.protocol = self.protocol
        if let name = self.name {
            protoEndpoint.system = name
        }
        protoEndpoint.hostname = self.host
        protoEndpoint.port = UInt32(self.port)
        proto.endpoint = protoEndpoint
        if let uid = self.uid {
            proto.nid = uid
        }
        return proto
    }

}
