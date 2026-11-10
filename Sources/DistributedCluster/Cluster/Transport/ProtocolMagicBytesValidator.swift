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

import Foundation
import Logging
import NIO
import NIOFoundationCompat
import NIOSSL
import SwiftProtobuf

/// Validates that the first two bytes for a new connection are equal to `kHandshakeMagicBytes`
/// and removes itself from the pipeline afterwards.
internal final class ProtocolMagicBytesValidator: ChannelInboundHandler, RemovableChannelHandler {
    internal typealias InboundIn = ByteBuffer
    internal typealias InboundOut = ByteBuffer

    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var bytes: ByteBuffer = self.unwrapInboundIn(data)
        do {
            guard let leadingBytes = bytes.readInteger(as: UInt16.self) else {
                throw WireFormatError.notEnoughBytes(expectedAtLeastBytes: 16 / 8, hint: "handshake magic bytes")
            }

            if leadingBytes != kHandshakeMagicBytes {
                throw HandshakeError.illegalHandshakeMagic(was: leadingBytes, expected: kHandshakeMagicBytes)
            }
            bytes.discardReadBytes()
            context.fireChannelRead(self.wrapInboundOut(bytes))
            context.pipeline.removeHandler(self, promise: nil)
        } catch {
            context.fireErrorCaught(error)
        }
    }
}
