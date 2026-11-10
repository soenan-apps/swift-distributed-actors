// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

/// Internal testing extensions allowing inspecting behavior internals
extension Behavior {
    // Similar to canonicalize but counts the nesting depth, be it in setup calls or interceptors.
    //
    // Implemented recursively and may stack overflow on insanely deep structures.
    // not all cases are covered, only enough to implement specific tests currently is.
    internal func nestingDepth(context: ActorContext<Message>) throws -> Int {
        func nestingDepth0(_ secondValue: Behavior<Message>) throws -> Int {
            switch secondValue.underlying {
            case .setup(let onStart):
                return try 1 + nestingDepth0(onStart(context))

            case .intercept(let inner, _):
                return try 1 + nestingDepth0(inner)

            case .signalHandling(let onMessage, _),
                .signalHandlingAsync(let onMessage, _):
                return try 1 + nestingDepth0(onMessage)

            case let .orElse(first, other):
                return 1 + max(try nestingDepth0(first), try nestingDepth0(other))

            case .suspended(let previousBehavior, _):
                return try 1 + nestingDepth0(previousBehavior)

            case .same,
                .receive, .receiveAsync,
                .receiveMessage, .receiveMessageAsync,
                .stop, .failed, .unhandled, .ignore, .suspend:
                return 1
            }
        }

        return try nestingDepth0(self)
    }

}
