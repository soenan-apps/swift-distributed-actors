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

import DistributedCluster
import Foundation
import NIO
import NIOFoundationCompat

internal final class CustomlyEncodedSerializer: Serializer<CustomlyEncodedMessage> {
    internal enum CodingError: Error {
        case notEnoughBytes
        case unknownEncoding(String)
    }

    private let allocator: NIO.ByteBufferAllocator

    private let availableRepr: ByteBuffer
    private let takenRepr: ByteBuffer

    internal init(_ allocator: ByteBufferAllocator) {
        self.allocator = allocator

        var availableBuffer: ByteBuffer = allocator.buffer(capacity: 1)  // <1>
        availableBuffer.writeStaticString("A")
        self.availableRepr = availableBuffer

        var takenBuffer: ByteBuffer = allocator.buffer(capacity: 1)
        takenBuffer.writeStaticString("T")
        self.takenRepr = takenBuffer
    }

    override internal func serialize(_ message: CustomlyEncodedMessage) -> Serialization.Buffer {  // <2>
        switch message {
        case .available:
        return .nioByteBuffer(self.availableRepr)

        case .taken:
        return .nioByteBuffer(self.takenRepr)
        }
    }

    override internal func deserialize(from buffer: Serialization.Buffer) throws -> CustomlyEncodedMessage {  // <3>
        guard case .nioByteBuffer(var byteBuffer) = buffer else {
            throw CodingError.unknownEncoding("expected ByteBuffer")
        }
        guard let letter = byteBuffer.readString(length: 1) else {
            throw CodingError.notEnoughBytes
        }

        switch letter {
        case "A":
        return .available

        case "T":
        return .taken

        default:
            throw CodingError.unknownEncoding(letter)
        }
    }
}
