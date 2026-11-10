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
internal class BoolSerializer: Serializer<Bool> {
    private let allocate: ByteBufferAllocator

    internal init(_ allocator: ByteBufferAllocator) {
        self.allocate = allocator
    }

    override internal func serialize(_ message: Bool) -> Serialization.Buffer {
        var buffer: ByteBuffer = self.allocate.buffer(capacity: 1)
        let value: Int8 = message ? 1 : 0
        buffer.writeInteger(value)
        return .nioByteBuffer(buffer)
    }

    override internal func deserialize(from buffer: Serialization.Buffer) throws -> Bool {
        switch buffer {
        case .data(let data):
            let integer: Int8 = data.withUnsafeBytes { $0.load(as: Int8.self) }
            return integer == 1

        case .nioByteBuffer(let buffer):
            guard let integer = buffer.getInteger(at: 0, endianness: .big, as: Int8.self) else {
                throw SerializationError(.notAbleToDeserialize(hint: "\(buffer) as \(Bool.self) (1/0 Int8)"))
            }
            return integer == 1

        case .nonExhaustive:
            throw SerializationError(
                .notAbleToDeserialize(hint: "\(Self.self) is [\(self)]. This should not happen, please file an issue.")
            )
        }
    }
}
