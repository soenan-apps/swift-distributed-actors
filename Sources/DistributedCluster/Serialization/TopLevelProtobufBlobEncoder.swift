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

import NIOFoundationCompat

import struct Foundation.Data
import struct NIO.ByteBuffer
import struct NIO.ByteBufferAllocator

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Top-Level Bytes-Blob Encoder

internal final class TopLevelProtobufBlobEncoder: TopLevelBlobEncoder {
    internal let allocator: ByteBufferAllocator

    internal var result: Serialization.Buffer?

    internal var codingPath: [CodingKey] {
        []
    }

    internal var userInfo: [CodingUserInfoKey: Any] = [:]

    internal init(allocator: ByteBufferAllocator) {
        self.allocator = allocator
    }

    internal func encode<T>(_ value: T) throws -> Serialization.Buffer where T: Encodable {
        var container: any SingleValueEncodingContainer = self.singleValueContainer()
        try container.encode(value)
        guard let result = self.result else {
            throw SerializationError(
                .unableToSerialize(
                    hint: "No bytes were written while encoding \(value) using \(Self.self)!"
                )
            )
        }
        return result
    }

    internal func store(data: Data) throws {
        guard self.result == nil else {
            throw SerializationError(
                .unableToSerialize(
                    hint: "Already encoded a single value, yet attempted to store another in \(Self.self)"
                )
            )
        }

        self.result = .data(data)
    }

    internal func store(buffer: ByteBuffer) throws {
        guard self.result == nil else {
            throw SerializationError(
                .unableToSerialize(
                    hint: "Already encoded a single value, yet attempted to store another in \(Self.self)"
                )
            )
        }

        self.result = .nioByteBuffer(buffer)
    }

    internal func store(bytes: [UInt8]) throws {
        guard self.result == nil else {
            throw SerializationError(
                .unableToSerialize(
                    hint: "Already encoded a single value, yet attempted to store another in \(Self.self)"
                )
            )
        }

        var byteBuffer: ByteBuffer = self.allocator.buffer(capacity: bytes.count)
        byteBuffer.writeBytes(bytes)
        self.result = .nioByteBuffer(byteBuffer)
    }

    internal func container<Key>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        fatalErrorBacktrace(
            "Cannot use KeyedEncodingContainer with \(Self.self), key type: \(reflecting: Key.self)",
            file: #file,
            line: #line
        )
    }

    internal func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalErrorBacktrace(
            "Attempted \(#function) in \(self)",
            file: #file,
            line: #line
        )
    }

    internal func singleValueContainer() -> SingleValueEncodingContainer {
        ProtobufBlobEncodingContainer(superEncoder: self)
    }
}
