// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Behavior {
    /// A stopped behavior ceases processing messages, which are drained to dead letters, and stops its actor.
    /// Return this behavior to stop your actors. The last assigned behavior
    /// will be used to handle the `PostStop` signal after the actor has stopped. This allows users to use
    /// the same signal handler (chain) to process all events.
    ///
    /// - SeeAlso: `stop(_:)` and `stop(postStop:) overloads for adding cleanup code to be executed upon receipt of
    /// PostStop signal.
    public static var stop: Behavior<Message> {
        Self.stop(reason: .stopMyself)
    }

    /// Runs once the actor has been started, also exposing the `ActorContext`
    ///
    /// #### Example usage
    /// ```
    /// .setup { context in
    ///     // e.g. spawn worker on startup:
    ///     let worker = try context.spawn("worker", (workerBehavior))
    ///
    ///     // it is safe to mutate actor "enclosed" state created e.g. during setup:
    ///     var workRequestsCounter = 0
    ///
    ///     return .receiveMessage { workRequest in
    ///          workRequestsCounter += 1
    ///         // do actual work...
    ///     }
    /// }
    /// ```
    ///
    /// This can be used to obtain the context, logger or perform actions right when the actor starts
    /// (e.g. send an initial message, or subscribe to some event stream, configure receive timeouts, etc.).
    public static func setup(_ onStart: @escaping (ActorContext<Message>) throws -> Behavior<Message>) -> Behavior {
        Behavior(underlying: .setup(onStart))
    }

    /// A stopped behavior ceases processing messages, which are drained to dead letters, and stops its actor.
    /// Return this behavior to stop your actors. This convenience overload
    /// allows users to specify a closure that will only be called on receipt of `PostStop` and therefore does not
    /// need to get the signal passed in or return a new behavior, as the actor is already stopping.
    public static func stop(_ postStop: @escaping (ActorContext<Message>) throws -> Void) -> Behavior<Message> {
        Self.stop(
            reason: .stopMyself,
            postStop: Self.receiveSignal { context, signal in
                if signal is Signals.PostStop {
                    try postStop(context)
                }
                return .stop  // will be ignored
            }
        )
    }

    /// A stopped behavior ceases processing messages, which are drained to dead letters, and stops its actor.
    /// Return this behavior to stop your actors. If a `postStop` behavior is
    /// set, it will be used to handle the `PostStop` signal after the actor has stopped. Otherwise the last
    /// assigned behavior will be used. This allows users to use the same signal handler (chain) to process
    /// all events.
    public static func stop(postStop: Behavior<Message>) -> Behavior<Message> {
        Behavior(underlying: .stop(postStop: postStop, reason: .stopMyself))
    }
}
