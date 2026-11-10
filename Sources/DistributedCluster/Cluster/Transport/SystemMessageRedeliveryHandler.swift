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

/// Handles `SystemMessage` re-delivery, by exchanging sequence numbered envelopes and (N)ACKs.
///
/// It follows the "Shell" pattern, all actual logic is implemented in the `OutboundSystemMessageRedelivery`
/// and `InboundSystemMessages`
internal final class SystemMessageRedeliveryHandler: ChannelDuplexHandler {
    internal typealias OutboundIn = TransportEnvelope
    internal typealias OutboundOut = TransportEnvelope

    internal typealias InboundIn = Wire.Envelope
    internal typealias InboundOut = Wire.Envelope
    // Buffer system messages until their delivery is acknowledged.
    internal enum TraceLogType: CustomStringConvertible {
        case inbound
        case outbound
        case outboundRedelivery

        internal var description: String {
            switch self {
            case .inbound:
                return "IN    "

            case .outbound:
                return "OUT   "

            case .outboundRedelivery:
                return "OUT-RE"
            }
        }
    }

    internal struct RedeliveryTick {}

    private let log: Logger
    private let system: ClusterSystem
    private let clusterShell: ClusterShell.Ref

    private let serializationPool: SerializationPool

    internal let outboundSystemMessages: OutboundSystemMessageRedelivery
    internal let inboundSystemMessages: InboundSystemMessages

    private var redeliveryScheduled: Scheduled<RedeliveryTick>?

    internal init(
        log: Logger,
        system: ClusterSystem,
        cluster: ClusterShell.Ref,
        serializationPool: SerializationPool,
        outbound: OutboundSystemMessageRedelivery,
        inbound: InboundSystemMessages
    ) {
        self.log = log
        self.system = system
        self.clusterShell = cluster
        self.serializationPool = serializationPool

        self.outboundSystemMessages = outbound
        self.inboundSystemMessages = inbound

        self.redeliveryScheduled = nil
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Outbound: Store System messages for re-delivery, pass along all other ones

    internal func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let transportEnvelope: TransportEnvelope = self.unwrapOutboundIn(data)

        guard case .systemMessage(let systemMessage) = transportEnvelope.storage else {
            // pass along any other messages
            context.write(data, promise: promise)
            return
        }

        switch self.outboundSystemMessages.offer(systemMessage, recipient: transportEnvelope.recipient) {
        case .send(let systemEnvelope):
            // message was additionally wrapped in redelivery system envelope, we shall push this rather than the
            // original serialization envelope;
            let redeliveryEnvelope: TransportEnvelope = TransportEnvelope(
                systemMessageEnvelope: systemEnvelope,
                recipient: transportEnvelope.recipient
            )

            self.tracelog(.outbound, message: redeliveryEnvelope)
            context.writeAndFlush(self.wrapOutboundOut(redeliveryEnvelope), promise: promise)

        case .bufferOverflowMustAbortAssociation:
            self.log.error(
                """
                Outbound system message queue overflow! MUST abort association, \
                system state integrity cannot be ensured (e.g. terminated signals may have been lost).
                """,
                metadata: [
                    "recipient": "\(transportEnvelope.recipient)"
                ]
            )
            self.clusterShell.tell(.command(.downCommand(transportEnvelope.recipient.node.endpoint)))
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Inbound system-message decoding

    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let wireEnvelope: Wire.Envelope = self.unwrapInboundIn(data)

        let messageType: Any.Type? = try? self.serializationPool.serialization.summonType(from: wireEnvelope.manifest)
        if messageType == SystemMessageEnvelope.self {
            self.deserializeThenHandle(type: SystemMessageEnvelope.self, wireEnvelope: wireEnvelope) { envelope in
                self.onInboundSystemMessage(context, systemEnvelope: envelope, wireEnvelope: wireEnvelope)
            }
        } else if messageType == SystemMessages.ACK.self {
            self.deserializeThenHandle(type: SystemMessages.ACK.self, wireEnvelope: wireEnvelope) { ack in
                self.onInboundACK(ack: ack)
            }
        } else if messageType == SystemMessages.NACK.self {
            self.deserializeThenHandle(type: SystemMessages.NACK.self, wireEnvelope: wireEnvelope) { nack in
                self.onInboundNACK(context, nack: nack)
            }
        } else if messageType == SystemMessages.self {
            log.error(
                """
                Received SystemMessages manifest! This should never happen, as system messages \
                should ALWAYS travel in `SystemMessageEnvelope`s. \
                Remote: \(reflecting: context.remoteAddress), manifest: \(wireEnvelope.manifest)
                """
            )
        } else {
            // it's a normal message, so we should directly pass it along
            context.fireChannelRead(self.wrapInboundOut(wireEnvelope))
        }
    }

    private func deserializeThenHandle<T>(type: T.Type, wireEnvelope: Wire.Envelope, callback: @escaping (T) -> Void) {
        self.serializationPool.deserializeAny(
            from: wireEnvelope.payload,
            using: wireEnvelope.manifest,
            recipientPath: wireEnvelope.recipient.path,
            callback: .init { result in
                self.tracelog(.inbound, message: wireEnvelope)
                switch result {
                case .success(.message(let message as T)):
                    callback(message)

                case .success(.message(let message)):
                    self.log.error("Unable to cast system message \(message) as \(T.self)!")

                case .success(.deadLetter(let message)):
                    self.log.error(
                        """
                        Deserialized as system message dead letter, this is highly suspect; \
                        Type \(type), wireEnvelope: \(wireEnvelope), message: \(message)
                        """
                    )

                case .failure(let error):
                    self.log.error("Failed to deserialize \(type), wireEnvelope: \(wireEnvelope), error: \(error)")
                }
            }
        )
    }

    private func onInboundSystemMessage(
        _ context: ChannelHandlerContext,
        systemEnvelope: SystemMessageEnvelope,
        wireEnvelope: Wire.Envelope
    ) {
        let recipient: ActorID = wireEnvelope.recipient

        switch self.inboundSystemMessages.onDelivery(systemEnvelope) {
        case .accept(let ack):
            // unwrap and immediately deliver the message; we do not need to forward it to the user-message handler
            let ref: AddressableActorRef = self.system.resolveUntyped(
                context: .init(id: wireEnvelope.recipient, system: self.system)
            )
            ref.sendSystemMessage(systemEnvelope.message)

            let ackEnvelope: TransportEnvelope = TransportEnvelope(ack: ack, recipient: recipient)
            self.tracelog(.outbound, message: ackEnvelope)
            context.writeAndFlush(self.wrapOutboundOut(ackEnvelope), promise: nil)

        case .gapDetectedRequestRedelivery(let nack):
            let nackEnvelope: TransportEnvelope = TransportEnvelope(nack: nack, recipient: recipient)
            self.tracelog(.outbound, message: nackEnvelope)
            context.writeAndFlush(self.wrapOutboundOut(nackEnvelope), promise: nil)

        case .acceptRedelivery(let ack):
            self.log.trace(
                """
                Received harmless re-delivery of already accepted message at \
                [sequenceNr: \(systemEnvelope.sequenceNr)]. Sending back [\(ack)].
                """
            )

            let ackEnvelope: TransportEnvelope = TransportEnvelope(ack: ack, recipient: recipient)
            self.tracelog(.outbound, message: ackEnvelope)
            context.writeAndFlush(self.wrapOutboundOut(ackEnvelope), promise: nil)
        }
    }

    private func onInboundACK(ack: SystemMessages.ACK) {
        switch self.outboundSystemMessages.acknowledge(ack) {
        case .acknowledged:
            return  // good, and do not pass the ACK through the pipeline, we handled it completely just now

        case .ackWasForFutureSequenceNr(let highestKnownSeqNr):
            self.log.warning(
                """
                Received unexpected system message [ACK(\(ack.sequenceNr))], while highest known (sent) \
                system message was [sequenceNr:\(highestKnownSeqNr)]. \
                Ignoring as harmless, however peer might be misbehaving.
                """
            )
        }
    }

    private func onInboundNACK(_ context: ChannelHandlerContext, nack: SystemMessages.NACK) {
        switch self.outboundSystemMessages.negativeAcknowledge(nack) {
        case .ensureRedeliveryTick(let nextRedeliveryTickDelay):
            self.scheduleNextRedeliveryTick(context, in: nextRedeliveryTickDelay)

        case .nothingToReDeliver:
            self.log.trace("Received NACK however no messages to redeliver.")

        case .nackWasForFutureSequenceNr(let highestKnownSeqNr):
            self.log.warning(
                """
                Received unexpected system message [NACK(\(nack.sequenceNr))], while highest known (sent) \
                system message was [sequenceNd:\(highestKnownSeqNr)]. \
                Ignoring as harmless, however peer migh be misbehaving.
                """
            )
        }
    }

    private func onRedeliveryTick(_ context: ChannelHandlerContext) {
        switch self.outboundSystemMessages.onRedeliveryTick() {
        case let .redeliver(envelopes, nextRedeliveryTickDelay):
            for redelivery in envelopes {
                self.tracelog(.outboundRedelivery, message: redelivery)
                context.write(self.wrapOutboundOut(redelivery), promise: nil)
            }
            context.flush()

            self.scheduleNextRedeliveryTick(context, in: nextRedeliveryTickDelay)

        }
    }

    private func scheduleNextRedeliveryTick(_ context: ChannelHandlerContext, in nextRedeliveryDelay: Duration) {
        guard self.redeliveryScheduled == nil else {
            return  // already a tick scheduled, we'll ride on that one rather than kick off a new one
        }

        self.redeliveryScheduled = context.eventLoop.scheduleTask(in: nextRedeliveryDelay.toNIO) {
            RedeliveryTick()
        }
        self.redeliveryScheduled?.futureResult.whenComplete { _ in
            self.redeliveryScheduled = nil
            self.onRedeliveryTick(context)
        }
    }
    /// Optional "dump all messages" logging.
    private func tracelog(
        _ type: TraceLogType,
        message: Any,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        let level: Logger.Level?
        switch type {
        case .outbound, .outboundRedelivery:
            level = self.outboundSystemMessages.settings.tracelogLevel

        case .inbound:
            level = self.inboundSystemMessages.settings.tracelogLevel
        }

        if let level = level {
            self.log.log(
                level: level,
                "[tracelog:sys-msg-redelivery] \(type.description): \(message)",
                file: file,
                function: function,
                line: line
            )
        }
    }
}
