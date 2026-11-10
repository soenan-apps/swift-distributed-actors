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

extension Cluster.Event: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoClusterEvent

    public init(fromProto proto: _ProtoClusterEvent, context: Serialization.Context) throws {
        switch proto.event {
        case .some(.membershipChange(let protoChange)):
            self = try .membershipChange(.init(fromProto: protoChange, context: context))

        case .some(.leadershipChange(let protoChange)):
            self = try .leadershipChange(.init(fromProto: protoChange, context: context))

        case .some(.snapshot(let protoMembership)):
            self = try .snapshot(.init(fromProto: protoMembership, context: context))

        case .none:
            fatalError("Unexpected attempt to serialize .none event in \(ProtobufRepresentation.self)")
        }
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoClusterEvent {
        var proto: _ProtoClusterEvent = _ProtoClusterEvent()

        switch self {
        case .snapshot(let membership):
            proto.event = .snapshot(try membership.toProto(context: context))

        case .membershipChange(let change):
            proto.event = .membershipChange(try change.toProto(context: context))

        case .leadershipChange(let change):
            // technically should not be gossiped around, but let us cover all the messages of Cluster.Event
            proto.event = .leadershipChange(try change.toProto(context: context))

        default:
            fatalError("Serialization not implemented for: \(self)")
        }

        return proto
    }
}

extension Cluster.MembershipChange: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoClusterMembershipChange

    public init(fromProto proto: ProtobufRepresentation, context: Serialization.Context) throws {
        guard proto.hasNode else {
            throw SerializationError(
                .missingField("node", type: "\(Cluster.MembershipChange.self)"),
                file: #fileID,
                line: #line
            )
        }

        self = try .init(
            node: .init(fromProto: proto.node, context: context),
            previousStatus: .init(fromProto: proto.fromStatus, context: context),
            toStatus: .init(fromProto: proto.toStatus, context: context)
        )
    }

    public func toProto(context: Serialization.Context) throws -> ProtobufRepresentation {
        var proto: _ProtoClusterMembershipChange = _ProtoClusterMembershipChange()

        proto.node = self.node.toProto(context: context)
        if let fromStatus = self.previousStatus {
            proto.fromStatus = try fromStatus.toProto(context: context)
        }
        proto.toStatus = try self.status.toProto(context: context)

        return proto
    }
}

extension Cluster.LeadershipChange: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoClusterLeadershipChange

    public init(fromProto proto: ProtobufRepresentation, context: Serialization.Context) throws {
        if proto.hasOldLeader {
            self.oldLeader = try Cluster.Member(fromProto: proto.oldLeader, context: context)
        } else {
            self.oldLeader = nil
        }

        if proto.hasNewLeader {
            self.newLeader = try Cluster.Member(fromProto: proto.newLeader, context: context)
        } else {
            self.newLeader = nil
        }
        #if DEBUG
        self.file = ""
        self.line = 0
        #endif
    }

    public func toProto(context: Serialization.Context) throws -> ProtobufRepresentation {
        var proto: ProtobufRepresentation = ProtobufRepresentation()

        if let old = self.oldLeader {
            proto.oldLeader = try old.toProto(context: context)
        }
        if let new = self.newLeader {
            proto.newLeader = try new.toProto(context: context)
        }

        return proto
    }
}
