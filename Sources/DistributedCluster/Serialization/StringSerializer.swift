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

import Foundation  // for Codable
import NIO
import NIOFoundationCompat
import SwiftProtobuf

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: String Serializer

@usableFromInline
internal class StringSerializer: Serializer<String> {
    private let allocate: ByteBufferAllocator

    internal init(_ allocator: ByteBufferAllocator) {
        self.allocate = allocator
    }

    override internal func serialize(_ message: String) -> Serialization.Buffer {
        let length: Int = message.lengthOfBytes(using: .utf8)
        var buffer: ByteBuffer = self.allocate.buffer(capacity: length)
        buffer.writeString(message)
        return .nioByteBuffer(buffer)
    }

    override internal func deserialize(from buffer: Serialization.Buffer) throws -> String {
        switch buffer {
        case .data(let data):
            guard let string = String(data: data, encoding: .utf8) else {
                throw SerializationError(.notAbleToDeserialize(hint: String(reflecting: String.self)))
            }
            return string

        case .nioByteBuffer(let buffer):
            guard let string = buffer.getString(at: 0, length: buffer.readableBytes) else {
                throw SerializationError(.notAbleToDeserialize(hint: String(reflecting: String.self)))
            }
            return string

        case .nonExhaustive:
            throw SerializationError(
                .notAbleToDeserialize(hint: "\(Self.self) is [\(self)]. This should not happen, please file an issue.")
            )
        }
    }
}
