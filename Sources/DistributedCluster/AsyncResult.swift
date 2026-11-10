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

import NIO

/// Abstraction over various types of asynchronous results, e.g. Futures or values completed by asynchronous callbacks,
/// or messages.
///
/// `AsyncResult` allows the actor to suspend itself until the result completes using `ActorContext.awaitResult`,
/// or _safely_ executing a callback on the actor's context by using `ActorContext.onResultAsync`.
///
/// - SeeAlso: `ActorContext.awaitResult`
/// - SeeAlso: `ActorContext.onResultAsync`
internal protocol AsyncResult {
    associatedtype Value

    /// **WARNING:** NOT end-user API.
    ///
    /// Unsafe to close over state: the closure's execution context is unspecified.
    /// Do not invoke it from an actor.
    /// Rather, use `context.onResultAsync` or `context.awaitResult` to handle this `AsyncResult`.
    ///
    /// Registers a callback that is executed when the `AsyncResult` is available.
    ///
    /// **CAUTION**: For testing purposes only. Not safe to use for actually running actors.
    func onComplete(_ callback: @escaping (Result<Value, Error>) -> Void)

    /// Returns a new `AsyncResult` that is completed with the value of this
    /// `AsyncResult`, or a `TimeoutError` when it is not completed within
    /// the specified timeout.
    ///
    /// If `self` already has a timeout attached, it will not
    /// be removed, so the lesser of the two timeouts will be the effective timeout
    /// value for the returned `AsyncResult`.
    ///
    /// - parameter timeout: defines a timeout after which the result should be considered failed.
    func withTimeout(after timeout: Duration) -> Self
}
