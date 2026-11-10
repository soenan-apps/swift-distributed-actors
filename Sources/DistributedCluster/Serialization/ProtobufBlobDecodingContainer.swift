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

internal struct ProtobufBlobDecodingContainer: SingleValueDecodingContainer {
    internal let superEncoder: TopLevelProtobufBlobDecoder

    internal private(set) var codingPath: [CodingKey] = []

    internal init(superEncoder: TopLevelProtobufBlobDecoder) {
        self.superEncoder = superEncoder
    }

    internal func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        guard let buffer = self.superEncoder.buffer else {
            fatalError("Super encoder has no bytes...!")
        }

        switch buffer {
        case .data(let data) where type is Foundation.Data.Type:
            guard let value = data as? T else {
                throw SerializationError(.unableToDeserialize(hint: "Expected \(type), decoded \(Data.self)"))
            }
            return value

        case .data where type is NIO.ByteBuffer.Type:
            guard let value = buffer.asByteBuffer(allocator: .init()) as? T else {
                throw SerializationError(.unableToDeserialize(hint: "Expected \(type), decoded \(ByteBuffer.self)"))
            }
            return value

        case .nioByteBuffer(let buffer) where type is NIO.ByteBuffer.Type:
            guard let value = buffer as? T else {
                throw SerializationError(.unableToDeserialize(hint: "Expected \(type), decoded \(ByteBuffer.self)"))
            }
            return value

        case .nioByteBuffer where type is Foundation.Data.Type:
            guard let value = buffer.readData() as? T else {
                throw SerializationError(.unableToDeserialize(hint: "Expected \(type), decoded \(Data.self)"))
            }
            return value

        default:
            throw SerializationError(
                .unableToDeserialize(
                    hint:
                        "Attempted decode \(reflecting: type) from a \(Self.self) which only supports raw bytes "
                        + "(ByteBuffer or Data) \(type is Foundation.Data.Type)"
                )
            )
        }
    }

    internal func decodeNil() -> Bool {
        false
    }

    internal func decode(_: Bool.Type) throws -> Bool {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: String.Type) throws -> String {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: Double.Type) throws -> Double {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: Float.Type) throws -> Float {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: Int.Type) throws -> Int {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: Int8.Type) throws -> Int8 {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: Int16.Type) throws -> Int16 {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: Int32.Type) throws -> Int32 {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: Int64.Type) throws -> Int64 {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: UInt.Type) throws -> UInt {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: UInt8.Type) throws -> UInt8 {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: UInt16.Type) throws -> UInt16 {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: UInt32.Type) throws -> UInt32 {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }

    internal func decode(_: UInt64.Type) throws -> UInt64 {
        throw SerializationError(
            .unableToDeserialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be deserialized by \(Self.self)!"
            )
        )
    }
}
