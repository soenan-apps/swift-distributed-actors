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

/// Configures buffering and retry intervals for outbound system messages.
public struct OutboundSystemMessageRedeliverySettings {
    /// Default buffering and one-second retry configuration.
    public static let `default`: OutboundSystemMessageRedeliverySettings = .init()

    /// When enabled, logs all outbound messages using the tracelog facility.
    /// Logs lines will be marked with: [tracelog:sys-msg-redelivery]
    internal let tracelogLevel: Logger.Level? = nil

    /// Configures the interval at which system messages will be re-delivered if no acknowledgement
    /// is received for them within that timeout.
    ///
    /// A single redelivery "burst" is limited by `redeliveryBurstMax`.
    internal var redeliveryInterval: Duration = .seconds(1)

    internal var makeRedeliveryBackoff: ConstantBackoffStrategy {
        Backoff.constant(self.redeliveryInterval)
    }

    /// Configures the maximum number (per association)
    internal var redeliveryBufferLimit: Int = 10_000

    /// Limits the maximum number of messages pushed out on one redelivery tick.
    internal var redeliveryBatchSize: Int = 500 {
        willSet {
            precondition(newValue > 0, "redeliveryBurstMax MUST be > 0")
        }
    }

}
