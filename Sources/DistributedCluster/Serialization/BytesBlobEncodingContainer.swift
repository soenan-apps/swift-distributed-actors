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

internal struct BytesBlobEncodingContainer: SingleValueEncodingContainer {
    internal private(set) var codingPath: [CodingKey] = []

    internal let superEncoder: TopLevelBytesBlobEncoder

    internal init(superEncoder: TopLevelBytesBlobEncoder) {
        self.superEncoder = superEncoder
    }

    internal func encode<T>(_ value: T) throws where T: Encodable {
        switch value {
        case let data as Data:
            try self.superEncoder.store(data: data)

        case let buffer as ByteBuffer:
            try self.superEncoder.store(buffer: buffer)

        case let bytes as [UInt8]:
            try self.superEncoder.store(bytes: bytes)

        default:
            throw SerializationError(
                .unableToSerialize(
                    hint: "Attempted encode \(T.self) into a \(Self.self) which only suports raw bytes"
                )
            )
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Not supported operations

    internal func encodeNil() throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) failed! Only a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: Bool) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: String) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: Double) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: Float) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: Int) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: Int8) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: Int16) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: Int32) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: Int64) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: UInt) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: UInt8) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: UInt16) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: UInt32) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }

    internal func encode(_ value: UInt64) throws {
        throw SerializationError(
            .unableToSerialize(
                hint: "\(#function) for \(value) failed! Only "
                    + "a top-level blob of bytes can be serialized by \(Self.self)!"
            )
        )
    }
}
