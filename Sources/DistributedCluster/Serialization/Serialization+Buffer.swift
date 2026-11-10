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

import CDistributedActorsMailbox
import Distributed
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf
import SWIM

extension Serialization {
    /// Container for serialization output.
    ///
    /// Describing what serializer was used to serialize the value, and its serialized bytes
    public struct Serialized {
        /// メッセージのワイヤー形式と型ヒント。
        public let manifest: Serialization.Manifest
        /// 符号化済みのメッセージバッファー。
        public let buffer: Serialization.Buffer
    }

    /// Abstraction of bytes containers.
    ///
    /// Designed to minimize allocation and copies when switching between different byte container types.
    public enum Buffer {
        /// Foundation Data が保持するバイト列。
        case data(Data)
        /// NIO ByteBuffer が保持するバイト列。
        case nioByteBuffer(ByteBuffer)

        /// 将来のバッファー表現を許容するための予約ケース。
        case nonExhaustive

        /// Number of bytes available in buffer
        public var count: Int {
            switch self {
            case .data(let data):
                return data.count

            case .nioByteBuffer(let buffer):
                return buffer.readableBytes

            case .nonExhaustive:
                fatalError("\(Self.self) is [\(self)]. This should not happen, please file an issue.")
            }
        }

        /// Convert the buffer to `Data`, this will copy in case the underlying buffer is a `ByteBuffer`
        public func readData() -> Data {
            switch self {
            case .data(let data):
                return data

            case .nioByteBuffer(let buffer):
                return Data(buffer.readableBytesView)

            case .nonExhaustive:
                fatalError("\(Self.self) is [\(self)]. This should not happen, please file an issue.")
            }
        }

        /// Convert the buffer to `NIO.ByteBuffer`, or return the underlying one if available.
        public func asByteBuffer(allocator: ByteBufferAllocator) -> ByteBuffer {
            switch self {
            case .data(let data):
                var buffer: ByteBuffer = allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)
                return buffer

            case .nioByteBuffer(let buffer):
                return buffer

            case .nonExhaustive:
                fatalError("\(Self.self) is [\(self)]. This should not happen, please file an issue.")
            }
        }
    }
}
