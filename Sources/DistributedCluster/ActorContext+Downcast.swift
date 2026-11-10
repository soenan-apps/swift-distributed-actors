// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO

extension ActorContext {
    /// INTERNAL API: UNSAFE, DO NOT TOUCH.
    @usableFromInline internal var downcastUnsafe: ActorShell<Message> {
        switch self {
        case let shell as ActorShell<Message>:
            return shell

        default:
            fatalError("""
                Illegal downcast attempt from \(String(reflecting: self)) to ActorCell. This is a \
                bug, please report this on the issue tracker.
                """)
        }
    }
}
