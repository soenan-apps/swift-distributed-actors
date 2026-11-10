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

import Logging
import NIO

/// Handler which simulates selective messages being lost or delayed.
/// Can be used to simulate system operation on bad network; useful for testing re-deliveries,
/// eventually consistent data-structures or consensus algorithms in face of lost messages.
internal final class FaultyNetworkSimulatingHandler: ChannelDuplexHandler {
    internal typealias InboundIn = Wire.Envelope
    internal typealias InboundOut = TransportEnvelope
    internal typealias OutboundIn = TransportEnvelope
    internal typealias OutboundOut = TransportEnvelope

    private let log: Logger
    private let settings: FaultyNetworkSimulationSettings

    /// The gremlin is responsible for dropping or delaying messages as defined by the configured mode.
    ///
    /// "But the most important rule, [...] no matter how much he begs, never feed him after midnight."
    private let gremlin: NetworkFaultGremlin

    internal init(log: Logger, settings: FaultyNetworkSimulationSettings) {
        self.log = log
        self.gremlin = NetworkFaultGremlin(settings: settings)
        self.settings = settings
    }

    internal func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message: InboundIn = self.unwrapInboundIn(data)

        switch self.gremlin.decide() {
        case .drop:
            self.log.log(
                level: self.settings.logLevel,
                "[faulty-network] IN  \(self.settings.effectiveLabel) \(self.settings.formatMessage(message))"
            )

        case .passThrough:
            context.fireChannelRead(data)
        }
    }

    internal func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message: OutboundIn = self.unwrapOutboundIn(data)

        switch self.gremlin.decide() {
        case .drop:
            self.log.log(
                level: self.settings.logLevel,
                "[faulty-network] OUT \(self.settings.effectiveLabel) \(self.settings.formatMessage(message))"
            )

        case .passThrough:
            context.write(data, promise: promise)
        }
    }
}
