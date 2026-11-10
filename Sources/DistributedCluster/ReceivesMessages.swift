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

import CDistributedActorsMailbox
import Dispatch
import Logging
import Metrics

import struct NIO.ByteBuffer

public protocol ReceivesMessages: Sendable, Codable {
    associatedtype Message: Codable
    /// Send message to actor referred to by this `ActorRef`.
    ///
    /// The symbolic version of "tell" is `!` and should also be pronounced as "tell".
    ///
    /// Note that `tell` is a "fire-and-forget" operation and does not block.
    /// The actor will eventually, asynchronously process the message sent to it.
    func tell(_ message: Message, file: String, line: UInt)
}
