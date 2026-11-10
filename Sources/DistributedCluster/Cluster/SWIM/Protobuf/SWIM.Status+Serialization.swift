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

extension SWIM.Status: @retroactive Decodable, @retroactive Encodable, ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoSWIMStatus

    public init(fromProto proto: _ProtoSWIMStatus, context: Serialization.Context) throws {
        switch proto.type {
        case .alive:
            self = .alive(incarnation: proto.incarnation)

        case .suspect:
            let suspectedBy: Set<ClusterMembership.Node> = try Set(
                proto.suspectedBy.map { nodeProto in
                    try ClusterMembership.Node(fromProto: nodeProto, context: context)
                }
            )
            self = .suspect(incarnation: proto.incarnation, suspectedBy: suspectedBy)

        case .unreachable:
            self = .unreachable(incarnation: proto.incarnation)

        case .dead:
            self = .dead

        case .unspecified:
            throw SerializationError(.missingField("type", type: String(describing: SWIM.Status.self)))

        case .UNRECOGNIZED(let num):
            throw SerializationError(.unknownEnumValue(num))
        }
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoSWIMStatus {
        var proto: _ProtoSWIMStatus = _ProtoSWIMStatus()
        switch self {
        case .alive(let incarnation):
            proto.type = .alive
            proto.incarnation = incarnation

        case let .suspect(incarnation, suspectedBy):
            proto.type = .suspect
            proto.incarnation = incarnation
            proto.suspectedBy = suspectedBy.map { $0.toProto(context: context) }

        case .unreachable(let incarnation):
            proto.type = .unreachable
            proto.incarnation = incarnation

        case .dead:
            proto.type = .dead
            proto.incarnation = 0
        }

        return proto
    }

}
