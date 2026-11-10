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

import NIO
import SwiftProtobuf

import struct Foundation.Data
import protocol Swift.Decoder  // to prevent shadowing by the ones in SwiftProtobuf
import protocol Swift.Encoder  // to prevent shadowing by the ones in SwiftProtobuf

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Protobuf serializers

/// Base protobuf serializer containing common logic, customizable by subclass.
open class BaseProtobufSerializer<Message, ProtobufMessage: SwiftProtobuf.Message>: Serializer<Message> {
    internal var contextStorage: Serialization.Context?
    internal var serializationContext: Serialization.Context {
        guard let context = self.contextStorage else {
            fatalError("Serialization.Context not available on \(self). This is a bug, please report.")
        }

        return context
    }

    override open func serialize(_ message: Message) throws -> Serialization.Buffer {
        let proto: ProtobufMessage = try self.toProto(message, context: self.serializationContext)
        return .data(try proto.serializedData())
    }

    override open func deserialize(from buffer: Serialization.Buffer) throws -> Message {
        let proto: ProtobufMessage = try ProtobufMessage(serializedBytes: buffer.readData())
        return try self.fromProto(proto, context: self.serializationContext)
    }

    /// メッセージを送信用の Protobuf 表現へ変換する。
    open func toProto(_: Message, context _: Serialization.Context) throws -> ProtobufMessage {
        undefined()
    }

    /// 受信した Protobuf 表現からメッセージを復元する。
    open func fromProto(_: ProtobufMessage, context _: Serialization.Context) throws -> Message {
        undefined()
    }

    /// 参照の解決に必要なコンテキストを設定する。
    override open func setSerializationContext(_ context: Serialization.Context) {
        self.contextStorage = context
    }
}
