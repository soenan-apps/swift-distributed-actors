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

internal class TopLevelProtobufSerializer<Message>: Serializer<Message> {
    internal let allocator: ByteBufferAllocator
    private let context: Serialization.Context

    internal init(allocator: ByteBufferAllocator, context: Serialization.Context) {
        self.allocator = allocator
        self.context = context
    }

    override internal func serialize(_ message: Message) throws -> Serialization.Buffer {
        guard let repr = message as? AnyProtobufRepresentable else {
            throw SerializationError(
                .unableToSerialize(
                    hint: "Can only serialize Any_InternalProtobufRepresentable types, was: "
                        + "\(String(reflecting: Message.self))"
                )
            )
        }

        let encoder: TopLevelProtobufBlobEncoder = TopLevelProtobufBlobEncoder(allocator: self.allocator)
        encoder.userInfo[.actorSystemKey] = self.context.system
        encoder.userInfo[.actorSerializationContext] = self.context
        try repr.encode(to: encoder)

        guard let buffer = encoder.result else {
            throw SerializationError(
                .unableToSerialize(
                    hint: "Encoding result of \(TopLevelBytesBlobEncoder.self) was empty, for message: \(message)"
                )
            )
        }

        traceLog_Serialization(
            "serialized to: \(buffer)",
            file: #fileID,
            line: #line
        )
        return buffer
    }

    override internal func deserialize(from _: Serialization.Buffer) throws -> Message {
        guard let protoType = Message.self as? AnyProtobufRepresentable.Type else {
            throw SerializationError(
                .unableToDeserialize(
                    hint: "Can only deserialize Any_InternalProtobufRepresentable but was \(Message.self)"
                )
            )
        }

        let decoder: TopLevelProtobufBlobDecoder = TopLevelProtobufBlobDecoder()
        decoder.userInfo[.actorSystemKey] = self.context.system
        decoder.userInfo[.actorSerializationContext] = self.context

        guard let message = try protoType.init(from: decoder) as? Message else {
            throw SerializationError(.unableToDeserialize(hint: "Decoded protobuf does not match \(Message.self)"))
        }
        return message
    }

    override internal func setSerializationContext(_: Serialization.Context) {
        // The serialization context is fixed when this serializer is initialized.
    }

    override internal func setUserInfo<Value>(key _: CodingUserInfoKey, value _: Value?) {
        // Protobuf decoding uses only the immutable serialization context above.
    }
}
