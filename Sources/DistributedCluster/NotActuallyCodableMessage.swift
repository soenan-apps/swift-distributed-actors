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

import struct NIO.ByteBuffer

/// Marks a type as `Codable` however attempting to send such message to a remote actor WILL FAIL and log an error.
///
/// Use this with great caution and only for messages which are specifically designed to utilize the local assumption.
///
/// DO NOT default to using this kind of messages in your system, as it makes the "move" from local to distributed
/// harder,
/// as eventually you realize you have to move messages to Codable or Protobuf backends. To avoid this surprise, always
/// default to actually serializable messages, and only use this type as an "opt out" for specific messages which
/// require it.
///
/// No serializer is expected to be registered for such types.
///
/// - Warning: Attempting to send such message over the network will fail at runtime (and log an error or warning).
public protocol NotActuallyCodableMessage: Codable {}

// Local-only Codable witnesses deliberately reject serialization at runtime.
// swiftlint:disable unavailable_function
extension NotActuallyCodableMessage {
    /// Local-only messages cannot be decoded from a serialization stream.
    public init(from _: Swift.Decoder) {
        fatalError("Attempted to decode NotActuallyCodableMessage message: \(Self.self)! This should never happen.")
    }

    /// Local-only messages cannot be reconstructed from a transport buffer.
    public init(
        context _: Serialization.Context,
        from _: inout ByteBuffer,
        using _: Serialization.Manifest
    ) {
        fatalError(
            "Attempted to deserialize NotActuallyCodableMessage message: \(Self.self)! This should never happen."
        )
    }

    /// Local-only messages cannot be encoded into a serialization stream.
    public func encode(to _: Swift.Encoder) {
        fatalError("Attempted to encode NotActuallyCodableMessage message: \(Self.self)! This should never happen.")
    }

    /// Local-only messages cannot be written into a transport buffer.
    public func serialize(context _: Serialization.Context, to _: inout ByteBuffer) {
        fatalError("Attempted to serialize NotActuallyCodableMessage message: \(Self.self)! This should never happen.")
    }
}
// swiftlint:enable unavailable_function
