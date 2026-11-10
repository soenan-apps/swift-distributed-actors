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

internal class TopLevelBytesBlobDecoder: TopLevelBlobDecoder {
    internal typealias Input = Serialization.Buffer

    internal private(set) var codingPath: [CodingKey] = []
    internal var userInfo: [CodingUserInfoKey: Any] = [:]

    internal func container<Key>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        throw SerializationError(.unableToDeserialize(hint: "Byte blobs do not contain keyed values"))
    }

    internal func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw SerializationError(.unableToDeserialize(hint: "Byte blobs do not contain unkeyed values"))
    }

    internal func singleValueContainer() -> SingleValueDecodingContainer {
        BytesBlobDecodingContainer(superEncoder: self)
    }

    internal func decode<T>(_: T.Type, from: Input) throws -> T where T: Decodable {
        try T.decodeSerialized(from: from, using: TopLevelProtobufBlobDecoder())
    }
}
