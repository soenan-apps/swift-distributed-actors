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

internal final class InitiatingHandshakeHandler: ChannelInboundHandler, RemovableChannelHandler {
    internal typealias InboundIn = ByteBuffer
    internal typealias InboundOut = ByteBuffer
    internal typealias OutboundOut = ByteBuffer

    private let log: Logger
    private let handshakeOffer: Wire.HandshakeOffer
    private let cluster: ClusterShell.Ref

    internal init(log: Logger, handshakeOffer: Wire.HandshakeOffer, cluster: ClusterShell.Ref) {
        self.log = log
        self.handshakeOffer = handshakeOffer
        self.cluster = cluster
    }

    internal func channelActive(context: ChannelHandlerContext) {
        self.initiateHandshake(context: context)
    }

    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.readHandshakeResponse(context: context, bytes: self.unwrapInboundIn(data))
    }

    private func initiateHandshake(context: ChannelHandlerContext) {
        let proto: _ProtoHandshakeOffer = _ProtoHandshakeOffer(self.handshakeOffer)
        self.log.trace("Offering handshake [\(proto)]")

        do {
            let bytes: ByteBuffer = try proto.serializedByteBuffer(allocator: context.channel.allocator)

            context.writeAndFlush(self.wrapOutboundOut(bytes), promise: nil)
        } catch {

            context.fireErrorCaught(error)
        }
    }

    private func readHandshakeResponse(context: ChannelHandlerContext, bytes: InboundIn) {
        var receivedBytes: ByteBuffer = bytes
        let metadata: Logger.Metadata = [
            "handshake/channel": "\(context.channel)"
        ]

        do {
            let response: Wire.HandshakeResponse = try self.readHandshakeResponse(bytes: &receivedBytes)
            switch response {
            case .accept(let accept):
                self.log.debug("Received handshake accept from: [\(reflecting: accept.targetNode)]", metadata: metadata)
                self.cluster.tell(.inbound(.handshakeAccepted(accept, channel: context.channel)))

                // handshake is completed, so we remove the handler from the pipeline
                context.pipeline.removeHandler(self, promise: nil)

            case .reject(let reject):
                self.log.debug(
                    """
                    Received handshake reject from: [\(reflecting: reject.targetNode)] \
                    reason: [\(reject.reason)], closing channel.
                    """,
                    metadata: metadata
                )
                self.cluster.tell(.inbound(.handshakeRejected(reject)))
                context.close(promise: nil)
            }
        } catch {
            self.log.debug(
                "Handshake failure, error [\(error)]:\(String(reflecting: type(of: error)))",
                metadata: metadata
            )
            self.cluster.tell(.inbound(.handshakeFailed(self.handshakeOffer.targetEndpoint, error)))
            _ = context.close(mode: .all)
        }
    }

    // length prefixed
    private func readHandshakeResponse(bytes: inout ByteBuffer) throws -> Wire.HandshakeResponse {
        guard let data = bytes.readData(length: bytes.readableBytes) else {
            throw WireFormatError.notEnoughBytes(expectedAtLeastBytes: bytes.readableBytes, hint: "handshake accept")
        }
        let proto: _ProtoHandshakeResponse = try _ProtoHandshakeResponse(serializedBytes: data)
        return try Wire.HandshakeResponse(proto)
    }
}
