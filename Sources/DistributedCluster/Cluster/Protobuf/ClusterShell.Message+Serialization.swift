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

import Foundation

extension ClusterShell.Message: InternalProtobufRepresentable {
    internal typealias ProtobufRepresentation = _ProtoClusterShellMessage

    internal init(fromProto proto: _ProtoClusterShellMessage, context: Serialization.Context) throws {
        switch proto.message {
        case .some(.clusterEvent(let protoEvent)):
            self = try .requestMembershipChange(.init(fromProto: protoEvent, context: context))

        case .some(.inbound(let inbound)):
            switch inbound.message {
            case .some(.restInPeace(let protoRIP)):
                self = try .inbound(
                    .restInPeace(
                        .init(fromProto: protoRIP.targetNode, context: context),
                        from: .init(fromProto: protoRIP.fromNode, context: context)
                    )
                )

            case .none:
                throw SerializationError(
                    .missingField("inbound.message", type: "\(_ProtoClusterInbound.self)"),
                    file: #fileID,
                    line: #line
                )
            }

        case .none:
            throw SerializationError(
                .missingField("message", type: "\(ProtobufRepresentation.self)"),
                file: #fileID,
                line: #line
            )
        }
    }

    internal func toProto(context: Serialization.Context) throws -> _ProtoClusterShellMessage {
        var proto: _ProtoClusterShellMessage = _ProtoClusterShellMessage()

        switch self {
        case .requestMembershipChange(let event):
            proto.clusterEvent = try event.toProto(context: context)

        case let .inbound(.restInPeace(target, from)):
            var protoRIP: _ProtoClusterRestInPeace = _ProtoClusterRestInPeace()
            protoRIP.targetNode = target.toProto(context: context)
            protoRIP.fromNode = from.toProto(context: context)
            var protoInbound: _ProtoClusterInbound = _ProtoClusterInbound()
            protoInbound.restInPeace = protoRIP
            proto.inbound = protoInbound

        default:
            fatalError("Serializer not implemented for: [\(self)]:\(String(reflecting: type(of: self)))")
        }
        return proto
    }
}
