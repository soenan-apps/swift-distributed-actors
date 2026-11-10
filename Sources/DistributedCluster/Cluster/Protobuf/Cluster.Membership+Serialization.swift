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

extension Cluster.Membership: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoClusterMembership

    public init(fromProto proto: _ProtoClusterMembership, context: Serialization.Context) throws {
        self.membersByNode = [:]
        self.membersByNode.reserveCapacity(proto.members.count)
        for protoMember in proto.members {
            let member: Cluster.Member = try Cluster.Member(fromProto: protoMember, context: context)
            self.membersByNode[member.node] = member
        }
        if proto.hasLeaderNode {
            self.leaderNode = Cluster.Node(fromProto: proto.leaderNode, context: context)
        } else {
            self.leaderNode = nil
        }
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoClusterMembership {
        var proto: ProtobufRepresentation = ProtobufRepresentation()
        proto.members = try self.membersByNode.values.map { member in
            try member.toProto(context: context)
        }
        if let leader = self.leader {
            proto.leaderNode = leader.node.toProto(context: context)
        }
        return proto
    }
}

extension Cluster.Member: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoClusterMember

    public init(fromProto proto: ProtobufRepresentation, context: Serialization.Context) throws {
        guard proto.hasNode else {
            throw SerializationError(
                .missingField("node", type: "\(ProtobufRepresentation.self)"),
                file: #fileID,
                line: #line
            )
        }
        self.node = .init(fromProto: proto.node, context: context)
        self.status = try .init(fromProto: proto.status, context: context)
        self.reachability = try .init(fromProto: proto.reachability, context: context)
        self.upNumber = proto.upNumber == 0 ? nil : Int(proto.upNumber)
    }

    public func toProto(context: Serialization.Context) throws -> ProtobufRepresentation {
        var proto: ProtobufRepresentation = ProtobufRepresentation()
        proto.node = self.node.toProto(context: context)
        proto.status = try self.status.toProto(context: context)
        proto.reachability = try self.reachability.toProto(context: context)
        if let number = self.upNumber {
            proto.upNumber = UInt32(number)
        }
        return proto
    }
}

extension Cluster.MemberReachability {

    internal init(fromProto proto: _ProtoClusterMemberReachability, context _: Serialization.Context) throws {
        switch proto {
        case .unspecified:
            throw SerializationError(
                .missingField("reachability", type: "\(_ProtoClusterMemberReachability.self)"),
                file: #fileID,
                line: #line
            )

        case .UNRECOGNIZED(let rawValue):
            throw SerializationError(
                .missingField("reachability:\(rawValue)", type: "\(_ProtoClusterMemberReachability.self)"),
                file: #fileID,
                line: #line
            )

        case .reachable:
            self = .reachable

        case .unreachable:
            self = .unreachable
        }
    }
    internal func toProto(context _: Serialization.Context) throws -> _ProtoClusterMemberReachability {
        switch self {
        case .reachable:
            return .reachable

        case .unreachable:
            return .unreachable

        case .nonExhaustive:
            throw SerializationError(
                .unableToSerialize(hint: "\(Self.self) is [\(self)]. This should not happen, please file an issue."),
                file: #fileID,
                line: #line
            )
        }
    }
}

extension Cluster.MemberStatus {

    internal init(fromProto proto: _ProtoClusterMemberStatus, context _: Serialization.Context) throws {
        switch proto {
        case .unspecified:
            throw SerializationError(
                .missingField("status", type: "\(_ProtoClusterMemberStatus.self)"),
                file: #fileID,
                line: #line
            )

        case .UNRECOGNIZED(let rawValue):
            throw SerializationError(
                .missingField("status:\(rawValue)", type: "\(_ProtoClusterMemberStatus.self)"),
                file: #fileID,
                line: #line
            )

        case .joining:
            self = .joining

        case .up:
            self = .operational

        case .leaving:
            self = .leaving

        case .down:
            self = .down

        case .removed:
            self = .removed
        }
    }
    internal func toProto(context _: Serialization.Context) throws -> _ProtoClusterMemberStatus {
        var proto: _ProtoClusterMemberStatus = _ProtoClusterMemberStatus()
        switch self {
        case .joining:
            proto = .joining

        case .operational:
            proto = .up

        case .leaving:
            proto = .leaving

        case .down:
            proto = .down

        case .removed:
            proto = .removed

        case .nonExhaustive:
            throw SerializationError(
                .unableToSerialize(hint: "\(Self.self) is [\(self)]. This should not happen, please file an issue."),
                file: #fileID,
                line: #line
            )
        }
        return proto
    }
}
