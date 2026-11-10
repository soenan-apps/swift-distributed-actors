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

import Foundation
import NIO

/// Eagerly or asynchronously completed response to an `ask` operation.
///
/// It is possible to `context.awaitResult` or `context.onResultAsync` on this type to safely consume it inside
/// the actors "single threaded illusion" context.
///
/// - warning: When exposing the underlying implementation and attaching callbacks to it, modifying or capturing
///            enclosing actor state is NOT SAFE, as the underlying future MAY not be scheduled on the same context
///            as the actor.
internal enum AskResponse<Value>: AsyncResult {
    case completed(Result<Value, Error>)

    /// **WARNING** Use with caution.
    ///
    /// Exposes underlying `NIO.EventLoopFuture`.
    ///
    /// - warning: DO NOT access or modify actor state from any of the future's callbacks as they MAY run concurrently
    /// to the actor.
    /// - warning: `AskResponse` may in the future no longer be backed by a NIO future and this option deprecated.
    case nioFuture(EventLoopFuture<Value>)
    /// Asynchronous value
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    internal var value: Value {
        get async throws {
            switch self {
            case let .completed(result):
                return try result.get()

            case let .nioFuture(nioFuture):
                return try await nioFuture.get()
            }
        }
    }
    /// Be very careful with using this as the resume will not run on the `ClusterSystem` provided actor context!
    /// // this will be solved when we move to swift concurrency as the actor runtime
    internal var unsafeAsyncValue: Value {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                onComplete { result in
                    continuation.resume(with: result)
                }
            }
        }
    }
    /// Blocks and waits until there is a response or fails with an error.
    @available(*, deprecated, message: "Blocking API will be removed in favor of async await")
    internal func wait() throws -> Value {
        switch self {
        case let .completed(result):
            return try result.get()

        case let .nioFuture(nioFuture):
            return try nioFuture.wait()
        }
    }
    internal func onComplete(_ callback: @escaping (Result<Value, Error>) -> Void) {
        switch self {
        case let .completed(result):
            callback(result)

        case let .nioFuture(nioFuture):
            nioFuture.onComplete { result in
                callback(result)
            }
        }
    }

    internal func withTimeout(after timeout: Duration) -> AskResponse<Value> {
        if timeout.isEffectivelyInfinite {
            return self
        }

        switch self {
        case .completed:
            return self

        case let .nioFuture(nioFuture):
            // ask errors should be lovely and include where they were asked from (source loc)
            let eventLoop: any EventLoop = nioFuture.eventLoop
            let promise: EventLoopPromise<Value> = eventLoop.makePromise()
            let timeoutTask: Scheduled<Void> = eventLoop.scheduleTask(in: timeout.toNIO) {
                promise.fail(
                    RemoteCallError(
                        .timedOut(
                            UUID(),
                            TimeoutError(
                                message: "\(type(of: self)) timed out after \(timeout.prettyDescription)",
                                timeout: timeout
                            )
                        )
                    )
                )
            }
            nioFuture.whenFailure { error in
                timeoutTask.cancel()
                promise.fail(error)
            }
            nioFuture.whenSuccess { value in
                timeoutTask.cancel()
                promise.succeed(value)
            }

            return .nioFuture(promise.futureResult)
        }
    }
    /// Transforms successful response of `Value` type to `NewValue` type.
    internal func map<NewValue>(_ callback: @escaping (Value) -> NewValue) -> AskResponse<NewValue> {
        switch self {
        case let .completed(result):
            switch result {
            case let .success(value):
                return .completed(.success(callback(value)))

            case let .failure(error):
                return .completed(.failure(error))
            }

        case let .nioFuture(nioFuture):
            return .nioFuture(nioFuture.map { callback($0) })
        }
    }
}
