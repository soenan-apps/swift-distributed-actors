// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Behavior {
    /// Creates a new Behavior which on an incoming message will first execute the first (current) behavior,
    /// and if it returns `.unhandled` applies the alternative behavior passed in here.
    ///
    /// If the alternative behavior contains a `.setup` or other deferred behavior, it will be canonicalized on its
    /// first execution.
    public func orElse(_ alternativeBehavior: Behavior<Message>) -> Behavior<Message> {
        Behavior(underlying: .orElse(first: self, second: alternativeBehavior))
    }
}
