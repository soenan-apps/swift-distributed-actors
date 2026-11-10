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

import class NIOExtras.LengthFieldBasedFrameDecoder
import class NIOExtras.LengthFieldPrepender

extension ClusterShell {
    internal func bootstrapServerSide(
        system: ClusterSystem,
        shell: ClusterShell.Ref,
        bindNode: Cluster.Node,
        settings: ClusterSystemSettings,
        serializationPool: SerializationPool
    ) -> EventLoopFuture<Channel> {
        let group: EventLoopGroup = settings.eventLoopGroup ?? settings.makeDefaultEventLoopGroup()

        let bootstrap: ServerBootstrap = ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in

                var channelHandlers: [(String?, ChannelHandler)]
                do {
                    channelHandlers = try self.serverTLSHandlers(settings: settings)
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }

                var log: Logger = system.log
                log[metadataKey: "actor/path"] = "/system/transport.server"

                let otherHandlers: [(String?, ChannelHandler)] = [
                    // reads go this way: vvv
                    ("magic validator", ProtocolMagicBytesValidator()),
                    ("framing writer", LengthFieldPrepender(lengthFieldLength: .four, lengthFieldEndianness: .big)),
                    ("framing reader", ByteToMessageHandler(
                        LengthFieldBasedFrameDecoder(lengthFieldLength: .four, lengthFieldEndianness: .big)
                    )),
                    ("receiving handshake handler", ReceivingHandshakeHandler(
                        log: log, cluster: shell, localNode: bindNode
                    )),
                ] + self.messageHandlers(log: log, system: system, shell: shell, serializationPool: serializationPool)

                channelHandlers.append(contentsOf: otherHandlers)

                return self.addChannelHandlers(channelHandlers, to: channel.pipeline)
            }

            // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        return bootstrap.bind(host: bindNode.endpoint.host, port: Int(bindNode.endpoint.port))
    }

    internal func bootstrapClientSide(
        system: ClusterSystem,
        shell: ClusterShell.Ref,
        handshake: TransportClientHandshake,
        settings: ClusterSystemSettings,
        serializationPool: SerializationPool
    ) -> EventLoopFuture<Channel> {
        let group: EventLoopGroup = settings.eventLoopGroup ?? settings.makeDefaultEventLoopGroup()

        let bootstrap: ClientBootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.connectTimeout, value: settings.connectTimeout.toNIO)
            .channelInitializer { channel in
                var channelHandlers: [(String?, ChannelHandler)]
                do {
                    channelHandlers = try self.clientTLSHandlers(settings: settings, endpoint: handshake.endpoint)
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }

                var log: Logger = system.log
                log[metadataKey: "actor/path"] = "/system/transport.client"

                let otherHandlers: [(String?, ChannelHandler)] = [
                    // reads go this way: vvv
                    ("magic prepender", ProtocolMagicBytesPrepender()),
                    ("framing writer", LengthFieldPrepender(lengthFieldLength: .four, lengthFieldEndianness: .big)),
                    ("framing reader", ByteToMessageHandler(
                        LengthFieldBasedFrameDecoder(lengthFieldLength: .four, lengthFieldEndianness: .big)
                    )),
                    ("initiating handshake handler", InitiatingHandshakeHandler(
                        log: log, handshakeOffer: handshake.offer, cluster: shell
                    )),
                ] + self.messageHandlers(log: log, system: system, shell: shell, serializationPool: serializationPool)

                channelHandlers.append(contentsOf: otherHandlers)

                return self.addChannelHandlers(channelHandlers, to: channel.pipeline)
            }

        return bootstrap.connect(host: handshake.endpoint.host, port: Int(handshake.endpoint.port))
    }

    private func serverTLSHandlers(settings: ClusterSystemSettings) throws -> [(String?, ChannelHandler)] {
        guard var tlsConfig = settings.tls else {
            return []
        }
        // Accepting sockets cannot know the connecting peer's hostname.
        if tlsConfig.certificateVerification == .fullVerification {
            tlsConfig.certificateVerification = .noHostnameVerification
        }
        let sslContext: NIOSSLContext = try self.makeSSLContext(
            fromConfig: tlsConfig, passphraseCallback: settings.tlsPassphraseCallback
        )
        let sslHandler: NIOSSLServerHandler = NIOSSLServerHandler(context: sslContext)
        return [("ssl", sslHandler)]
    }

    private func messageHandlers(
        log: Logger,
        system: ClusterSystem,
        shell: ClusterShell.Ref,
        serializationPool: SerializationPool
    ) -> [(String?, ChannelHandler)] {
        let outbound: OutboundSystemMessageRedelivery = OutboundSystemMessageRedelivery(settings: .default)
        let inbound: InboundSystemMessages = InboundSystemMessages(settings: .default)
        return [
            ("wire envelope handler", WireEnvelopeHandler(
                serialization: serializationPool.serialization, log: log
            )),
            ("outbound serialization handler", OutboundSerializationHandler(
                log: log, serializationPool: serializationPool
            )),
            ("system message re-delivery", SystemMessageRedeliveryHandler(
                log: log,
                system: system,
                cluster: shell,
                serializationPool: serializationPool,
                outbound: outbound,
                inbound: inbound
            )),
            ("actor message handler", UserMessageHandler(
                log: log, system: system, serializationPool: serializationPool
            )),
        ]
    }

    private func clientTLSHandlers(
        settings: ClusterSystemSettings,
        endpoint: Cluster.Endpoint
    ) throws -> [(String?, ChannelHandler)] {
        guard let tlsConfig = settings.tls else {
            return []
        }
        let targetHost: String? = tlsConfig.certificateVerification == .fullVerification ? endpoint.host : nil
        let sslContext: NIOSSLContext = try self.makeSSLContext(
            fromConfig: tlsConfig, passphraseCallback: settings.tlsPassphraseCallback
        )
        let sslHandler: NIOSSLClientHandler = try NIOSSLClientHandler(
            context: sslContext, serverHostname: targetHost
        )
        return [("ssl", sslHandler)]
    }

    private func addChannelHandlers(
        _ handlers: [(String?, ChannelHandler)],
        to pipeline: ChannelPipeline
    ) -> EventLoopFuture<Void> {

        pipeline.eventLoop.traverseIgnore(over: handlers) { name, handler in
            pipeline.addHandler(handler, name: name)
        }
    }

    private func makeSSLContext(
        fromConfig tlsConfig: TLSConfiguration,
        passphraseCallback: NIOSSLPassphraseCallback<[UInt8]>?
    ) throws -> NIOSSLContext {
        if let tlsPassphraseCallback = passphraseCallback {
            return try NIOSSLContext(configuration: tlsConfig, passphraseCallback: tlsPassphraseCallback)
        }
        return try NIOSSLContext(configuration: tlsConfig)
    }
}
