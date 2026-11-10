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

extension SWIM.PingResponse: @retroactive Decodable, @retroactive Encodable, ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoSWIMPingResponse

    public init(fromProto proto: _ProtoSWIMPingResponse, context: Serialization.Context) throws {
        guard let pingResponse = proto.pingResponse else {
            throw SerializationError(.missingField("pingResponse", type: String(describing: SWIM.PingResponse.self)))
        }
        switch pingResponse {
        case .ack(let ack):
            let target: ClusterMembership.Node = try ClusterMembership.Node(fromProto: ack.target, context: context)
            let payload: SWIM.GossipPayload = try SWIM.GossipPayload(fromProto: ack.payload, context: context)
            let sequenceNumber: SWIM.SequenceNumber = ack.sequenceNumber
            self = .ack(target: target, incarnation: ack.incarnation, payload: payload, sequenceNumber: sequenceNumber)

        case .nack(let nack):
            let target: ClusterMembership.Node = try ClusterMembership.Node(fromProto: nack.target, context: context)
            let sequenceNumber: SWIM.SequenceNumber = nack.sequenceNumber
            self = .nack(target: target, sequenceNumber: sequenceNumber)
        }
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoSWIMPingResponse {
        var proto: _ProtoSWIMPingResponse = _ProtoSWIMPingResponse()
        switch self {
        case let .ack(target, incarnation, payload, sequenceNumber):
            var ack: _ProtoSWIMPingResponse.Ack = _ProtoSWIMPingResponse.Ack()
            ack.target = target.toProto(context: context)
            ack.incarnation = incarnation
            ack.payload = try payload.toProto(context: context)
            ack.sequenceNumber = sequenceNumber
            proto.ack = ack

        case let .nack(target, sequenceNumber):
            var nack: _ProtoSWIMPingResponse.Nack = _ProtoSWIMPingResponse.Nack()
            nack.target = target.toProto(context: context)
            nack.sequenceNumber = sequenceNumber
            proto.nack = nack

        case .timeout:
            throw SerializationError(.nonTransportableMessage(type: "\(self)"))
        }
        return proto
    }

}
