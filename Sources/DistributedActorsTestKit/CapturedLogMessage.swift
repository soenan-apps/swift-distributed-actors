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

import DistributedActorsConcurrencyHelpers
import XCTest

import struct Foundation.Date

@testable import DistributedCluster
@testable import Logging

/// A log event retained by a test capture.
public struct CapturedLogMessage {
    /// Time at which the message was captured.
    public let date: Date
    /// Message severity.
    public let level: Logger.Level
    /// Renderable log message.
    public var message: Logger.Message
    /// Metadata merged from the handler and event.
    public var metadata: Logger.Metadata?
    /// Originating source file.
    public let file: String
    /// Originating function.
    public let function: String
    /// Originating source line.
    public let line: UInt
}
