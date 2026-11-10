// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

import Dispatch
import NIO

/// Selects the executor used to process an actor's messages.
internal enum DispatcherProps {
    /// Lets the runtime determine the default dispatcher.
    case `default`
    /// Dispatcher which runs on the calling thread.
    case callingThread
    case dispatchQueue(DispatchQueue)
    /// Binds execution to the supplied event loop group.
    case nio(NIO.EventLoopGroup)
    /// Requests a dedicated thread for this actor.
    case pinnedThread

    internal var name: String {
        switch self {
        case .default:
            return "default"

        case .pinnedThread:
            return "pinnedThread"

        case .nio:
            return "nioEventLoopGroup"

        case .dispatchQueue:
            return "dispatchQueue"

        case .callingThread:
            return "callingThread"
        }
    }
}
