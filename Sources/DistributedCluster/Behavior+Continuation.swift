// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Behavior {
    /// Defines that the "same" behavior should remain in use for handling the next message.
    ///
    /// Note: prefer returning `.same` rather than "the same instance" of a behavior, as `.same` is internally optimized
    /// to avoid allocating and swapping behavior states when no changes are needed to be made.
    public static var same: Behavior<Message> {
        Behavior(underlying: .same)
    }

    // and their logging rate should be configurable
    /// Causes a message to be assumed unhandled by the runtime.
    /// Unhandled messages are logged by default, and other behaviors may use this information to implement
    /// `apply1.orElse(apply2)` style logic.
    public static var unhandled: Behavior<Message> {
        Behavior(underlying: .unhandled)
    }

    /// Ignore an incoming message.
    ///
    /// Ignoring a message differs from handling it with "unhandled" since the latter can be acted upon by
    /// another behavior, such as "orElse" for behavior composition. `ignore` consumes the message:
    /// we did handle it, but chose to ignore it.
    ///
    /// Returning `ignore` implies remaining the same behavior, the same way as would returning `.same`.
    public static var ignore: Behavior<Message> {
        Behavior(underlying: .ignore)
    }
}
