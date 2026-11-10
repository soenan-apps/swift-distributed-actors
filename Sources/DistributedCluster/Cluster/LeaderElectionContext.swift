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

/// Context supplied to an election by the actor driving it.
public struct LeaderElectionContext {
    /// Logger scoped to the actor driving the election.
    public var log: Logger
    /// Event loop used to complete election results.
    public let loop: EventLoop

    internal init<M>(_ ownerContext: ActorContext<M>) {
        self.log = ownerContext.log
        self.loop = ownerContext.system.eventLoopGroup.next()
    }

    internal init(log: Logger, eventLoop: EventLoop) {
        self.log = log
        self.loop = eventLoop
    }
}
