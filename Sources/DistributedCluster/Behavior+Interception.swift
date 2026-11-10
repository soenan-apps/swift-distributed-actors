// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Behavior {
    /// Intercepts all incoming messages and signals, allowing to transform them before they are delivered to the
    /// wrapped behavior.
    public static func intercept(
        behavior: Behavior<Message>,
        with interceptor: Interceptor<Message>
    ) -> Behavior<Message> {
        Behavior(underlying: .intercept(behavior: behavior, with: interceptor))
    }
}
