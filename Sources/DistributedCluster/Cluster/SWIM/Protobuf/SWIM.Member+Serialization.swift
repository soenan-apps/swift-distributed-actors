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

extension SWIM.Member: @retroactive Decodable, @retroactive Encodable, ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoSWIMMember

    public init(fromProto proto: _ProtoSWIMMember, context: Serialization.Context) throws {
        let node: ClusterMembership.Node = try ClusterMembership.Node(fromProto: proto.node, context: context)
        let status: SWIM.Status = try SWIM.Status(fromProto: proto.status, context: context)
        let protocolPeriod: UInt64 = proto.protocolPeriod
        self.init(node: node, status: status, protocolPeriod: protocolPeriod)
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoSWIMMember {
        var proto: _ProtoSWIMMember = _ProtoSWIMMember()
        proto.node = self.node.toProto(context: context)
        proto.status = try self.status.toProto(context: context)
        proto.protocolPeriod = self.protocolPeriod
        return proto
    }

}
