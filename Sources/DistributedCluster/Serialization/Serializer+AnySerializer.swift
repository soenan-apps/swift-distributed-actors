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

import CDistributedActorsMailbox
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf

extension Serializer: AnySerializer {

    /// 型消去したインターフェイスとして公開する。
    public var asAnySerializer: AnySerializer {
        BoxedAnySerializer(self)
    }

    /// 型消去されたメッセージを検査して符号化する。
    public func trySerialize(_ message: Any) throws -> Serialization.Buffer {
        guard let typedMessage = message as? Message else {
            throw SerializationError(
                .wrongSerializer(
                    hint: """
                        Attempted to serialize message type [\(String(reflecting: type(of: message)))] \
                        as [\(String(reflecting: Message.self))], which do not match! Serializer: [\(self)]
                        """
                )
            )
        }

        return try self.serialize(typedMessage)
    }

    /// バッファーを復号して型消去された値を返す。
    public func tryDeserialize(_ buffer: Serialization.Buffer) throws -> Any {
        try self.deserialize(from: buffer)
    }
}
