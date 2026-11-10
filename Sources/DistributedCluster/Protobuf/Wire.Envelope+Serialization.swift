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
import NIO
import SwiftProtobuf

import struct Foundation.Data  // would refer to not go "through" Data as our target always is ByteBuffer

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: _ProtoEnvelope

extension Wire.Envelope: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoEnvelope

    internal init(fromProto proto: ProtobufRepresentation, context: Serialization.Context) throws {
        guard proto.hasRecipient else {
            throw WireEnvelopeError.emptyRecipient
        }
        guard proto.hasManifest else {
            throw WireEnvelopeError.missingManifest
        }

        self.recipient = try ActorID(fromProto: proto.recipient, context: context)
        self.payload = .data(proto.payload)
        self.manifest = .init(fromProto: proto.manifest)
    }

    public func toProto(context: Serialization.Context) throws -> ProtobufRepresentation {
        var proto: ProtobufRepresentation = ProtobufRepresentation()
        proto.recipient = try self.recipient.toProto(context: context)

        proto.manifest = .init()
        if let hint = self.manifest.hint {
            proto.manifest.hint = hint
        }
        proto.manifest.serializerID = self.manifest.serializerID.value
        proto.payload = self.payload.readData()
        return proto
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: _ProtoProtocolVersion
// conversions are naive here, we'd want to express this more nicely...
extension Wire.Version {
    internal init(_ proto: _ProtoProtocolVersion) {
        self.reserved = UInt8(proto.reserved)
        self.major = UInt8(proto.major)
        self.minor = UInt8(proto.minor)
        self.patch = UInt8(proto.patch)
    }
}

extension _ProtoProtocolVersion {
    internal init(_ value: Wire.Version) {
        var proto: _ProtoProtocolVersion = _ProtoProtocolVersion()
        proto.reserved = UInt32(value.reserved)
        proto.major = UInt32(value.major)
        proto.minor = UInt32(value.minor)
        proto.patch = UInt32(value.patch)
        self = proto
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: _ProtoHandshakeAccept
extension Wire.HandshakeAccept {
    internal init(_ proto: _ProtoHandshakeAccept) throws {
        guard proto.hasVersion else {
            throw SerializationError(
                .missingField("version", type: String(describing: Wire.HandshakeAccept.self))
            )
        }
        guard proto.hasTargetNode else {
            throw SerializationError(
                .missingField("targetNode", type: String(describing: Wire.HandshakeAccept.self))
            )
        }
        guard proto.hasOriginNode else {
            throw SerializationError(
                .missingField("originNode", type: String(describing: Wire.HandshakeAccept.self))
            )
        }
        self.version = .init(proto.version)
        self.targetNode = try .init(proto.targetNode)
        self.originNode = try .init(proto.originNode)
        self.onHandshakeReplySent = nil
    }
}

extension _ProtoHandshakeAccept {
    internal init(_ accept: Wire.HandshakeAccept) {
        self.version = .init(accept.version)
        self.targetNode = .init(accept.targetNode)
        self.originNode = .init(accept.originNode)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: _ProtoHandshakeReject
extension Wire.HandshakeReject {
    internal init(_ proto: _ProtoHandshakeReject) throws {
        guard proto.hasVersion else {
            throw SerializationError(
                .missingField("version", type: String(describing: Wire.HandshakeReject.self))
            )
        }
        guard proto.hasTargetNode else {
            throw SerializationError(
                .missingField("targetNode", type: String(describing: Wire.HandshakeReject.self))
            )
        }
        guard proto.hasOriginNode else {
            throw SerializationError(
                .missingField("originNode", type: String(describing: Wire.HandshakeReject.self))
            )
        }

        self.version = .init(proto.version)
        self.targetNode = try .init(proto.targetNode)
        self.originNode = try .init(proto.originNode)
        self.onHandshakeReplySent = nil
        self.reason = proto.reason
    }
}

extension _ProtoHandshakeReject {
    internal init(_ reject: Wire.HandshakeReject) {
        self.version = .init(reject.version)
        self.targetNode = .init(reject.targetNode)
        self.originNode = .init(reject.originNode)
        self.reason = reject.reason
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: HandshakeOffer
// worth making it Proto representable or not?
extension Wire.HandshakeOffer {
    internal typealias ProtobufRepresentation = _ProtoHandshakeOffer

    internal init(fromProto proto: _ProtoHandshakeOffer) throws {
        guard proto.hasOriginNode else {
            throw SerializationError(
                .missingField("originNode", type: String(reflecting: Wire.HandshakeOffer.self))
            )
        }
        guard proto.hasTargetEndpoint else {
            throw SerializationError(
                .missingField("targetEndpoint", type: String(reflecting: Wire.HandshakeOffer.self))
            )
        }
        guard proto.hasVersion else {
            throw SerializationError(
                .missingField("version", type: String(reflecting: Wire.HandshakeOffer.self))
            )
        }

        self.originNode = try Cluster.Node(proto.originNode)
        self.targetEndpoint = Cluster.Endpoint(proto.targetEndpoint)
        self.version = Wire.Version(
            reserved: UInt8(proto.version.reserved),
            major: UInt8(proto.version.major),
            minor: UInt8(proto.version.minor),
            patch: UInt8(proto.version.patch)
        )
    }
}

extension _ProtoHandshakeOffer {
    internal init(_ offer: Wire.HandshakeOffer) {
        self.version = _ProtoProtocolVersion(offer.version)
        self.originNode = _ProtoClusterNode(offer.originNode)
        self.targetEndpoint = _ProtoClusterEndpoint(offer.targetEndpoint)
    }

    internal init(serializedData data: Data) throws {
        var proto: _ProtoHandshakeOffer = _ProtoHandshakeOffer()
        try proto.merge(serializedBytes: data)

        guard proto.hasVersion else {
            throw SerializationError(
                .missingField("version", type: String(reflecting: Wire.HandshakeOffer.self))
            )
        }
        guard proto.hasOriginNode else {
            throw SerializationError(
                .missingField("hasOriginNode", type: String(reflecting: Wire.HandshakeOffer.self))
            )
        }
        guard proto.hasTargetEndpoint else {
            throw SerializationError(
                .missingField("targetEndpoint", type: String(reflecting: Wire.HandshakeOffer.self))
            )
        }

        self = proto
    }
}
