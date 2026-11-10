// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Behavior {
    /// Allows handling signals such as termination or lifecycle events.
    @usableFromInline
    internal static func signalHandling(
        handleMessage: Behavior<Message>,
        handleSignal: @escaping (ActorContext<Message>, Signal) throws -> Behavior<Message>
    ) -> Behavior<Message> {
        Behavior(underlying: .signalHandling(handleMessage: handleMessage, handleSignal: handleSignal))
    }

    /// Allows handling signals such as termination or lifecycle events.
    @usableFromInline
    internal static func signalHandlingAsync(
        handleMessage: Behavior<Message>,
        handleSignal: @escaping @Sendable (ActorContext<Message>, Signal) async throws -> Behavior<Message>
    ) -> Behavior<Message> {
        Behavior(underlying: .signalHandlingAsync(handleMessage: handleMessage, handleSignal: handleSignal))
    }

    /// Causes an actor to go into suspended state.
    ///
    /// 型消去された再開結果を登録時の結果型へ戻してからhandlerへ渡す。
    /// 保存する前に`.suspended`へcanonicalizeする必要がある。
    @usableFromInline
    internal static func suspend<T>(
        handler: @escaping (Result<T, Error>) throws -> Behavior<Message>
    ) -> Behavior<Message> {
        Behavior(
            underlying: .suspend { result in
                try handler(
                    result.map { value in
                        guard let resumedValue = value as? T else {
                            preconditionFailure("Resume result does not match suspended type \(T.self)")
                        }
                        return resumedValue
                    }
                )
            }
        )
    }

    /// Represents a behavior in suspended state.
    ///
    /// A suspended actor will only react to system messages, until it is resumed.
    /// This usually happens when an async operation that caused the suspension
    /// is completed.
    @usableFromInline
    internal static func suspended(
        previousBehavior: Behavior<Message>,
        handler: @escaping (Result<Any, Error>) throws -> Behavior<Message>
    ) -> Behavior<Message> {
        Behavior(underlying: .suspended(previousBehavior: previousBehavior, handler: handler))
    }

    /// Creates internal representation of stopped behavior, see `stop(_:)` for public api.
    internal static func stop(reason: StopReason, postStop: Behavior<Message>? = nil) -> Behavior<Message> {
        Behavior(underlying: .stop(postStop: postStop, reason: reason))
    }

    /// Internal way of expressing a failed actor, retains the behavior that has failed internally.
    ///
    /// - parameters
    ///   - error: cause of the actor's failing.
    internal func fail(cause: Supervision.Failure) -> Behavior<Message> {
        Behavior(underlying: BehaviorKind<Message>.failed(behavior: self, cause: cause))
    }
}
