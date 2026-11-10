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

import struct Foundation.Data
import struct NIO.ByteBuffer
import struct NIO.ByteBufferAllocator

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Top-Level Bytes-Blob Encoder

internal struct BytesBlobDecodingContainer: SingleValueDecodingContainer {
    internal let superEncoder: TopLevelBytesBlobDecoder

    internal private(set) var codingPath: [CodingKey] = []

    internal init(superEncoder: TopLevelBytesBlobDecoder) {
        self.superEncoder = superEncoder
    }

    internal func decode<T>(_: T.Type) throws -> T where T: Decodable {
        throw SerializationError(.unableToDeserialize(hint: "Cannot decode \(T.self) from \(Self.self)"))
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
