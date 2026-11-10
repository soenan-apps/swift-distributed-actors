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

internal final class ReceivingHandshakeHandler: ChannelInboundHandler, RemovableChannelHandler {
    internal typealias InboundIn = ByteBuffer
    internal typealias InboundOut = Never

    private let log: Logger
    private let cluster: ClusterShell.Ref
    private let localNode: Cluster.Node

    internal init(log: Logger, cluster: ClusterShell.Ref, localNode: Cluster.Node) {
        self.log = log
        self.cluster = cluster
        self.localNode = localNode
    }

    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        do {
            var bytes: ByteBuffer = self.unwrapInboundIn(data)
            let offer: Wire.HandshakeOffer = try self.readHandshakeOffer(bytes: &bytes)

            let metadata: Logger.Metadata = [
                "handshake/channel": "\(context.channel)"
            ]

            self.log.debug(
                """
                Received handshake offer from: [\(reflecting: offer.originNode)] \
                with protocol version: [\(offer.version)]
                """,
                metadata: metadata
            )

            let promise: EventLoopPromise<Wire.HandshakeResponse> = context.eventLoop.makePromise()
            self.cluster.tell(.inbound(.handshakeOffer(offer, channel: context.channel, handshakeReplyTo: promise)))

            promise.futureResult.whenComplete { res in
                switch res {
                case .success(.accept(let accept)):
                    do {
                        self.log.debug("Write accept handshake to: [\(offer.originNode)]", metadata: metadata)
                        try self.writeHandshakeAccept(context, accept)
                    } catch {
                        self.log.error("Failed when sending Handshake.Accept: \(accept), error: \(error)")
                        context.fireErrorCaught(error)
                    }

                case .success(.reject(let reject)):
                    do {
                        self.log.debug(
                            "Write reject handshake offer to: [\(offer.originNode)] reason: [\(reject.reason)]",
                            metadata: metadata
                        )
                        try self.writeHandshakeReject(context, reject)
                    } catch {
                        self.log.error("Failed when writing \(reject), error: \(error)", metadata: metadata)
                        context.fireErrorCaught(error)
                    }

                case .failure(let err):
                    context.fireErrorCaught(err)

                }
            }
        } catch {
            context.fireErrorCaught(error)
        }
    }

    private func readHandshakeOffer(bytes: inout ByteBuffer) throws -> Wire.HandshakeOffer {
        guard let data = bytes.readData(length: bytes.readableBytes) else {
            throw WireFormatError.notEnoughBytes(expectedAtLeastBytes: bytes.readableBytes, hint: "handshake offer")
        }
        let proto: _ProtoHandshakeOffer = try _ProtoHandshakeOffer(serializedBytes: data)
        return try Wire.HandshakeOffer(fromProto: proto)
    }

    private func writeHandshakeAccept(_ context: ChannelHandlerContext, _ accept: Wire.HandshakeAccept) throws {
        var proto: _ProtoHandshakeResponse = _ProtoHandshakeResponse()
        proto.accept = _ProtoHandshakeAccept(accept)

        let bytes: ByteBuffer = try proto.serializedByteBuffer(allocator: context.channel.allocator)
        context.writeAndFlush(NIOAny(bytes), promise: nil)
        accept.onHandshakeReplySent?()

        // Continue with envelope processing once the handshake completes.
        context.pipeline.removeHandler(self, promise: nil)
    }

    private func writeHandshakeReject(_ context: ChannelHandlerContext, _ reject: Wire.HandshakeReject) throws {
        var proto: _ProtoHandshakeResponse = _ProtoHandshakeResponse()
        proto.reject = _ProtoHandshakeReject(reject)

        let bytes: ByteBuffer = try proto.serializedByteBuffer(allocator: context.channel.allocator)
        context.writeAndFlush(NIOAny(bytes), promise: nil)
        reject.onHandshakeReplySent?()

        // Continue with envelope processing once the handshake completes.
        context.pipeline.removeHandler(self, promise: nil)
    }
}
