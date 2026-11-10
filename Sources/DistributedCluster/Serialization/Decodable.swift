// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Foundation  // JSON and PList coders
import NIO
import NIOFoundationCompat

extension Decodable {
    internal static func decodeSerialized(
        from buffer: Serialization.Buffer, using decoder: JSONDecoder
    ) throws -> Self {
        try decoder.decode(Self.self, from: buffer.readData())
    }

    internal static func decodeSerialized<C>(
        from container: inout C,
        forKey key: C.Key,
        using _: Decoder
    ) throws -> Self
    where C: KeyedDecodingContainerProtocol {
        try container.decode(Self.self, forKey: key)
    }
}

extension Decodable {
    internal static func decodeSerialized(
        from buffer: Serialization.Buffer,
        using decoder: PropertyListDecoder,
        format initialFormat: PropertyListSerialization.PropertyListFormat
    ) throws -> Self {
        var format: PropertyListSerialization.PropertyListFormat = initialFormat
        return try decoder.decode(Self.self, from: buffer.readData(), format: &format)
    }
}

extension Decodable {
    internal static func decodeSerialized(
        from buffer: Serialization.Buffer,
        using decoder: TopLevelBytesBlobDecoder
    ) throws -> Self {
        try decoder.decode(Self.self, from: buffer)
    }
}

extension Decodable {
    internal static func decodeSerialized(
        from buffer: Serialization.Buffer,
        using decoder: TopLevelProtobufBlobDecoder
    ) throws -> Self {
        try decoder.decode(Self.self, from: buffer)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Encodable + encodeSerialized(bytes:using:SomeDecoder) extensions

extension Encodable {
    internal func encodeSerialized(using encoder: JSONEncoder) throws -> Data {
        try encoder.encode(self)
    }
}

extension Encodable {
    internal func encodeSerialized(using encoder: PropertyListEncoder) throws -> Data {
        try encoder.encode(self)
    }
}

extension Encodable {
    internal func encodeSerialized(using encoder: TopLevelBytesBlobEncoder) throws -> Serialization.Buffer {
        try encoder.encode(self)
    }
}

extension Encodable {
    internal func encodeSerialized(using encoder: TopLevelProtobufBlobEncoder) throws -> Serialization.Buffer {
        try encoder.encode(self)
    }
}
