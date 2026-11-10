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

/// Sends `kHandshakeMagicBytes` as the first two bytes for a new connection
/// and remove itself from the pipeline afterwards.
internal final class ProtocolMagicBytesPrepender: ChannelOutboundHandler, RemovableChannelHandler {
    internal typealias OutboundIn = ByteBuffer
    internal typealias OutboundOut = ByteBuffer

    internal func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var buffer: ByteBuffer = context.channel.allocator.buffer(capacity: 2)
        buffer.writeInteger(kHandshakeMagicBytes, endianness: .big)
        context.write(self.wrapOutboundOut(buffer), promise: nil)

        context.writeAndFlush(data, promise: promise)
        context.pipeline.removeHandler(self, promise: nil)
    }
}
