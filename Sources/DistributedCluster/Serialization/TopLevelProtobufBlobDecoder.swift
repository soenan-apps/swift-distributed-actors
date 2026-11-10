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

internal class TopLevelProtobufBlobDecoder: TopLevelBlobDecoder {
    internal typealias Input = ByteBuffer

    internal private(set) var codingPath: [CodingKey] = []
    internal var userInfo: [CodingUserInfoKey: Any] = [:]

    internal var buffer: Serialization.Buffer?

    internal func container<Key>(keyedBy _: Key.Type) -> KeyedDecodingContainer<Key> where Key: CodingKey {
        fatalErrorBacktrace(
            "\(#function) has not been implemented",
            file: #file,
            line: #line
        )
    }

    internal func unkeyedContainer() -> UnkeyedDecodingContainer {
        fatalErrorBacktrace(
            "\(#function) has not been implemented",
            file: #file,
            line: #line
        )
    }

    internal func singleValueContainer() -> SingleValueDecodingContainer {
        ProtobufBlobDecodingContainer(superEncoder: self)
    }

    internal func decode<T>(_ type: T.Type, from buffer: Serialization.Buffer) throws -> T where T: Decodable {
        self.buffer = buffer

        if let protoType = type as? AnyProtobufRepresentable.Type {
            guard let value = try protoType.init(from: self) as? T else {
                throw SerializationError(.unableToDeserialize(hint: "Decoded protobuf does not match \(type)"))
            }
            return value
        }
        if let protoType = type as? AnyPublicProtobufRepresentable.Type {
            guard let value = try protoType.init(from: self) as? T else {
                throw SerializationError(.unableToDeserialize(hint: "Decoded protobuf does not match \(type)"))
            }
            return value
        }
        return fatalErrorBacktrace(
            "\(Self.self) is not able to decode \(T.self) as it isn't a ProtobufRepresentable type!",
            file: #file,
            line: #line
        )
    }
}
