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

import Distributed
import DistributedActorsConcurrencyHelpers
import Foundation
import Logging

/// Message carrying all information needed to log a log statement issued by a `Logger`.
///
/// This can be used to offload the action of actually writing the log statements to an asynchronous worker actor.
/// This is useful to not block the (current) actors processing with any potential IO operations a `LogHandler` may
/// need to perform.
internal struct LogMessage {
    internal let identifier: String

    internal let time: Date
    internal let level: Logger.Level
    internal let message: Logger.Message
    internal var effectiveMetadata: Logger.Metadata?

    internal let file: String
    internal let function: String
    internal let line: UInt
}
