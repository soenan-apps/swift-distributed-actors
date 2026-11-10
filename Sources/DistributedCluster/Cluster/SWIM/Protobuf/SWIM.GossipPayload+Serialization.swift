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

extension SWIM.GossipPayload: @retroactive Decodable, @retroactive Encodable, ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoSWIMGossipPayload

    public init(fromProto proto: _ProtoSWIMGossipPayload, context: Serialization.Context) throws {
        if proto.member.isEmpty {
            self = .none
        } else {
            let members: [SWIM.Member] = try proto.member.map { memberProto in
                try SWIM.Member(fromProto: memberProto, context: context)
            }
            self = .membership(members)
        }
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoSWIMGossipPayload {
        var payload: _ProtoSWIMGossipPayload = _ProtoSWIMGossipPayload()
        if case .membership(let members) = self {
            payload.member = try members.map { member in
                try member.toProto(context: context)
            }
        }

        return payload
    }

}
