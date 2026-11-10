// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2020 Apple Inc. and the Swift Distributed Actors project authors
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

import struct Foundation.Data
import protocol Swift.Decoder  // to prevent shadowing by the ones in SwiftProtobuf
import protocol Swift.Encoder  // to prevent shadowing by the ones in SwiftProtobuf

/// This protocol is for internal protobuf-serializable messages only.
///
/// A separate protocol keeps internal protobuf messages out of the public type surface.
internal protocol InternalProtobufRepresentable: AnyProtobufRepresentable {
    associatedtype ProtobufRepresentation: SwiftProtobuf.Message

    init(from decoder: Decoder) throws
    init(fromProto proto: ProtobufRepresentation, context: Serialization.Context) throws
    func encode(to encoder: Encoder) throws

    func toProto(context: Serialization.Context) throws -> ProtobufRepresentation
}

extension InternalProtobufRepresentable {
    internal init(from decoder: Decoder) throws {
        guard let context = decoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(decoder, Self.self)
        }

        let container: any SingleValueDecodingContainer = try decoder.singleValueContainer()

        let data: Data = try container.decode(Data.self)
        let proto: ProtobufRepresentation = try ProtobufRepresentation(serializedBytes: data)

        try self.init(fromProto: proto, context: context)
    }
    internal init(
        context: Serialization.Context, from buffer: Serialization.Buffer, using _: Serialization.Manifest
    ) throws {
        let proto: ProtobufRepresentation = try ProtobufRepresentation(serializedBytes: buffer.readData())
        try self.init(fromProto: proto, context: context)
    }
    internal func encode(to encoder: Encoder) throws {
        guard let context = encoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(encoder, self)
        }

        var container: any SingleValueEncodingContainer = encoder.singleValueContainer()

        let proto: ProtobufRepresentation = try self.toProto(context: context)
        let data: Data = try proto.serializedData()

        try container.encode(data)
    }
    internal func serialize(context: Serialization.Context) throws -> Serialization.Buffer {
        try .data(self.toProto(context: context).serializedData())
    }
}
