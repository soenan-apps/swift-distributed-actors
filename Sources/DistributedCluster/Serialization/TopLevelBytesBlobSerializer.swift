// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Foundation  // for Codable
import NIO
import NIOFoundationCompat

/// Allows for serialization of a *single* blob at the top level.
/// Used for messages encoded using external serializers, such as protobuf, flat buffers or similar.
public class TopLevelBytesBlobSerializer<Message: Codable>: Serializer<Message> {
    internal let allocator: ByteBufferAllocator

    private let context: Serialization.Context

    public init(allocator: ByteBufferAllocator, context: Serialization.Context, type _: Message.Type = Message.self) {
        self.allocator = allocator
        self.context = context
    }

    override public func serialize(_ message: Message) throws -> Serialization.Buffer {
        let encoder: TopLevelBytesBlobEncoder = TopLevelBytesBlobEncoder(allocator: self.allocator)
        encoder.userInfo[.actorSystemKey] = self.context.system
        encoder.userInfo[.actorSerializationContext] = self.context
        try message.encode(to: encoder)
        guard let bytes = encoder.result else {
            throw SerializationError(
                .unableToSerialize(
                    hint: "Encoding result of \(TopLevelBytesBlobEncoder.self) was empty, for message: \(message)"
                )
            )
        }

        traceLog_Serialization(
            "serialized to: \(bytes)",
            file: #fileID,
            line: #line
        )
        return bytes
    }

    override public func deserialize(from buffer: Serialization.Buffer) throws -> Message {
        let decoder: TopLevelBytesBlobDecoder = TopLevelBytesBlobDecoder()
        decoder.userInfo[.actorSystemKey] = self.context.system
        decoder.userInfo[.actorSerializationContext] = self.context

        return try Message.decodeSerialized(from: buffer, using: decoder)
    }
}
