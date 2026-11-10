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

/// Configures tracing for inbound system-message delivery.
public struct InboundSystemMessageRedeliverySettings {
    /// Default tracing configuration.
    public static let `default`: Self = Self()

    /// When enabled, logs all outbound messages using the tracelog facility.
    /// Logs lines will be marked with: [tracelog:sys-msg-redelivery]
    internal let tracelogLevel: Logger.Level? = nil
}
