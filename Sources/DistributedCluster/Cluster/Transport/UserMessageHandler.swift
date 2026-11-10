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

/// Deserializes and delivers user messages (i.e. anything that is not a system message).
internal final class UserMessageHandler: ChannelInboundHandler {
    internal typealias InboundIn = Wire.Envelope
    internal typealias InboundOut = Never  // we terminate here, by sending messages off to local actors

    internal let log: Logger

    internal let system: ClusterSystem
    internal let serializationPool: SerializationPool

    internal init(log: Logger, system: ClusterSystem, serializationPool: SerializationPool) {
        self.log = log
        self.system = system
        self.serializationPool = serializationPool
    }

    /// This ends the processing chain for incoming messages.
    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let wireEnvelope: Wire.Envelope = self.unwrapInboundIn(data)
        let manifestMessageType: Any.Type? = try? self.serializationPool.serialization
            .summonType(from: wireEnvelope.manifest)

        switch manifestMessageType {
        case .some(is InvocationMessage.Type):
            do {
                let invocation: InvocationMessage = try self.serializationPool.serialization.deserialize(
                    as: InvocationMessage.self, from: wireEnvelope.payload, using: wireEnvelope.manifest
                )
                self.system.receiveInvocation(invocation, recipient: wireEnvelope.recipient, on: context.channel)
            } catch {
                self.system.log.error("Failed to deserialize [\(InvocationMessage.self)]: \(error)")
            }

        case .some(is any AnyRemoteCallReply.Type):
            do {
                let reply: any AnyRemoteCallReply = try self.serializationPool.serialization.deserialize(
                    as: (any AnyRemoteCallReply).self, from: wireEnvelope.payload, using: wireEnvelope.manifest
                )
                self.system.receiveRemoteCallReply(reply)
            } catch {
                self.system.log.error("Failed to deserialize [\(String(describing: manifestMessageType))]: \(error)")
            }

        default:
            self.deserializeThenDeliver(context, wireEnvelope: wireEnvelope)
        }
    }

    private func deserializeThenDeliver(_: ChannelHandlerContext, wireEnvelope: Wire.Envelope) {
        // It is OF CRUCIAL IMPORTANCE that we do not accidentally attempt to deserialize an `Any.Type`.
        // We must ensure that we deserialize using the actual type that was expected by the destination actor.
        // This can be done by obtaining the serializer that is bound to a specific type by using the Manifest.
        //
        // Since we are receiving a message:
        // 1. We must have spawned an actor of this type -- it must have ensured a serializer for this manifest
        // 2. We have ensured a serializer for it otherwise
        // X. We never spawned or registered the serializer and the message shall be dropped

        // 1. Resolve the actor, it MUST be local and MUST contain the actual Message type it expects
        let ref: AddressableActorRef = self.system.resolveUntyped(
            context: .init(id: wireEnvelope.recipient, system: self.system)
        )
        // We resolved "untyped" meaning that we did not take into account the Type of the actor when looking for it.
        // However, the actor ref "inside" has strict knowledge about what specific Message type it is about (!).

        // all other messages are "normal" and should be delivered to the target actor normally
        ref.deserializeDeliver(
            wireEnvelope.payload,
            using: wireEnvelope.manifest,
            on: self.serializationPool
        )
    }
}
