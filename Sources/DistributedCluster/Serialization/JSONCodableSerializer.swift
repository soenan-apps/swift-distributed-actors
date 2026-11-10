// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift Distributed Actors project authors
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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: JSON

/// Allows for serialization of messages using the Foundation's `JSONEncoder` and `JSONDecoder`.
///
/// - Note: Take care to ensure that both "ends" (sending and receiving members of a cluster)
///   use the same encoding/decoding mechanism for a specific message.
internal class JSONCodableSerializer<Message: Codable>: Serializer<Message> {
    internal var encoder: JSONEncoder
    internal var decoder: JSONDecoder

    internal init(encoder: JSONEncoder = .init(), decoder: JSONDecoder = .init()) {
        self.encoder = encoder
        self.decoder = decoder
    }

    override internal func serialize(_ message: Message) throws -> Serialization.Buffer {
        let data: Data = try encoder.encode(message)
        traceLog_Serialization(
            "serialized to: \(data)",
            file: #fileID,
            line: #line
        )
        return .data(data)
    }

    override internal func deserialize(from buffer: Serialization.Buffer) throws -> Message {
        try self.decoder.decode(Message.self, from: buffer.readData())
    }

    override internal func setSerializationContext(_ context: Serialization.Context) {
        // same context shared for encoding/decoding is safe
        self.decoder.userInfo[.actorSystemKey] = context.system
        self.decoder.userInfo[.actorSerializationContext] = context

        self.encoder.userInfo[.actorSystemKey] = context.system
        self.encoder.userInfo[.actorSerializationContext] = context
    }

    override internal func setUserInfo<Value>(key: CodingUserInfoKey, value: Value?) {
        self.encoder.userInfo[key] = value
        self.decoder.userInfo[key] = value
    }
}
