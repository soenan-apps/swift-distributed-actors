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

@usableFromInline
internal class IntegerSerializer<Number: FixedWidthInteger>: Serializer<Number> {
    private let allocate: ByteBufferAllocator

    internal init(_: Number.Type, _ allocator: ByteBufferAllocator) {
        self.allocate = allocator
    }

    override internal func serialize(_ message: Number) -> Serialization.Buffer {
        var buffer: ByteBuffer = self.allocate.buffer(capacity: MemoryLayout<Number>.size)
        buffer.writeInteger(message, endianness: .big, as: Number.self)
        return .nioByteBuffer(buffer)
    }

    override internal func deserialize(from buffer: Serialization.Buffer) throws -> Number {
        switch buffer {
        case .data(let data):
            return Number(bigEndian: data.withUnsafeBytes { $0.loadUnaligned(as: Number.self) })

        case .nioByteBuffer(let buffer):
            guard let integer = buffer.getInteger(at: 0, endianness: .big, as: Number.self) else {
                throw SerializationError(.notAbleToDeserialize(hint: "\(buffer) as \(Number.self)"))
            }
            return integer

        case .nonExhaustive:
            throw SerializationError(
                .notAbleToDeserialize(hint: "\(Self.self) is [\(self)]. This should not happen, please file an issue.")
            )
        }
    }
}
