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

internal final class OutboundSerializationHandler: ChannelOutboundHandler {
    internal typealias OutboundIn = TransportEnvelope
    internal typealias OutboundOut = Wire.Envelope

    internal let log: Logger
    internal let serializationPool: SerializationPool

    internal init(log: Logger, serializationPool: SerializationPool) {
        self.log = log
        self.serializationPool = serializationPool
    }

    internal func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        self.serializeThenWrite(context, envelope: self.unwrapOutboundIn(data), promise: promise)
    }

    private func serializeThenWrite(
        _ context: ChannelHandlerContext,
        envelope transportEnvelope: TransportEnvelope,
        promise: EventLoopPromise<Void>?
    ) {
        let serializationPromise: EventLoopPromise<Serialization.Serialized> = context.eventLoop.makePromise()

        self.serializationPool.serialize(
            message: transportEnvelope.underlyingMessage,
            recipientPath: transportEnvelope.recipient.path,
            promise: serializationPromise
        )

        serializationPromise.futureResult.whenComplete { result in
            switch result {
            case .success(let serialized):
                let wireEnvelope: Wire.Envelope = Wire.Envelope(
                    recipient: transportEnvelope.recipient,
                    payload: serialized.buffer,
                    manifest: serialized.manifest
                )
                context.write(self.wrapOutboundOut(wireEnvelope), promise: promise)

            case .failure(let error):
                self.log.error(
                    "Serialization of outgoing message failed: \(error)",
                    metadata: [
                        "message": "\(transportEnvelope.underlyingMessage)",
                        "message/type": .string("\(reflecting: type(of: transportEnvelope.underlyingMessage as Any))"),
                        "recipient": "\(transportEnvelope.recipient)",
                    ]
                )

                promise?.fail(error)
            }
        }
    }
}
