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

internal final class WireEnvelopeHandler: ChannelDuplexHandler {
    internal typealias OutboundIn = Wire.Envelope
    internal typealias OutboundOut = ByteBuffer
    internal typealias InboundIn = ByteBuffer
    internal typealias InboundOut = Wire.Envelope

    internal let log: Logger
    internal let serialization: Serialization

    internal init(serialization: Serialization, log: Logger) {
        self.serialization = serialization
        self.log = log
    }

    internal func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let envelope: Wire.Envelope = self.unwrapOutboundIn(data)
        do {
            let serialized: Serialization.Serialized = try serialization.serialize(envelope)
            let buffer: ByteBuffer = serialized.buffer.asByteBuffer(allocator: self.serialization.allocator)
            context.writeAndFlush(NIOAny(buffer), promise: promise)
        } catch {
            self.log.error(
                "Failed to serialize message!",
                metadata: [
                    "message": "\(envelope)",
                    "error": "\(error)",
                ]
            )
            context.fireErrorCaught(error)
        }
    }

    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer: ByteBuffer = self.unwrapInboundIn(data)
        do {
            let knownSpecializedWireEnvelopeManifest: Serialization.Manifest = Serialization.Manifest(
                serializerID: .protobufRepresentable, hint: Wire.Envelope.typeHint
            )
            let envelope: Wire.Envelope = try self.serialization.deserialize(
                as: Wire.Envelope.self, from: .nioByteBuffer(buffer), using: knownSpecializedWireEnvelopeManifest
            )
            context.fireChannelRead(self.wrapInboundOut(envelope))
        } catch {
            self.log.error(
                "Failed to deserialize message",
                metadata: [
                    "buffer": "\(buffer)",
                    "error": "\(error)",
                ]
            )
            context.fireErrorCaught(error)
        }
    }
}
