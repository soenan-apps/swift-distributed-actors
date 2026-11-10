// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Logging

/// Used for the internal ability to schedule a callback to be executed by an actor.
@usableFromInline
internal struct AsynchronousCallback<T> {
    @usableFromInline internal let callback: (T) throws -> Void
    @usableFromInline internal let send: (@escaping () throws -> Void) -> Void

    internal init(callback: @escaping (T) throws -> Void, send: @escaping (@escaping () throws -> Void) -> Void) {
        self.callback = callback
        self.send = send
    }

    @inlinable
    internal func invoke(_ arg: T) {
        self.send { try callback(arg) }
    }
}
