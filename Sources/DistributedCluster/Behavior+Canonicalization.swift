// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

// Internal operations for behavior manipulation.
extension Behavior {
    /// Shorthand for checking if the current behavior is a `.unhandled`
    internal var isUnhandled: Bool {
        switch self.underlying {
        case .unhandled:
            return true

        default:
            return false
        }
    }

    /// Shorthand for checking if the `Behavior` is `.stop` or `.failed`.
    internal var isTerminal: Bool {
        switch self.underlying {
        case .stop, .failed:
            return true

        default:
            return false
        }
    }

    /// Shorthand for checking if the `Behavior` is NOT `.stop` or `.failed`.
    internal var isStillAlive: Bool {
        !self.isTerminal
    }

    internal var isSuspend: Bool {
        switch self.underlying {
        case .suspend:
            return true

        default:
            return false
        }
    }

    internal var isSuspended: Bool {
        switch self.underlying {
        case .suspended:
            return true

        default:
            return false
        }
    }

    internal var isSame: Bool {
        switch self.underlying {
        case .same:
            return true

        default:
            return false
        }
    }

    internal var isSetup: Bool {
        switch self.underlying {
        case .setup:
            return true

        default:
            return false
        }
    }

    /// Returns `false` if canonicalizing behavior is known to not create a change in behavior.
    /// For example `.same` or semantically equivalent behaviors.
    internal var isChanging: Bool {
        switch self.underlying {
        case .same, .ignore, .unhandled:
            return false

        default:
            return true
        }
    }

    internal func interpretOrElse(
        context: ActorContext<Message>,
        first: Behavior<Message>,
        orElse second: Behavior<Message>,
        message: Message,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Behavior<Message> {
        var nextBehavior: Behavior<Message> = try first.interpretMessage(
            context: context,
            message: message,
            file: file,
            line: line
        )
        if nextBehavior.isUnhandled {
            nextBehavior = try second.interpretMessage(
                context: context,
                message: message,
                file: file,
                line: line
            )
        }
        return nextBehavior
    }

    /// Applies `interpretMessage` to an iterator of messages, while canonicalizing the behavior after every reduction.
    internal func interpretMessages<Iterator: IteratorProtocol>(
        context: ActorContext<Message>,
        messages: inout Iterator
    ) throws -> Behavior<Message> where Iterator.Element == Message {
        var currentBehavior: Behavior<Message> = self
        while currentBehavior.isStillAlive {
            if let message = messages.next() {
                let nextBehavior: Behavior<Message> = try currentBehavior.interpretMessage(
                    context: context,
                    message: message
                )
                currentBehavior = try currentBehavior.canonicalize(context, next: nextBehavior)
            } else {
                break
            }
        }

        return currentBehavior
    }

    /// Validate if a Behavior is legal to be used as "initial" behavior (when an Actor is spawned),
    /// since certain behaviors do not make sense as initial behavior.
    internal func validateAsInitial() throws {
        switch self.underlying {
        case .same:
            throw IllegalBehaviorError.notAllowedAsInitial(self)

        case .unhandled:
            throw IllegalBehaviorError.notAllowedAsInitial(self)

        default:
            return ()
        }
    }

    /// Same as `validateAsInitial`, however useful in chaining expressions as it returns itself when the validation has
    /// passed successfully.
    internal func validatedAsInitial() throws -> Behavior<Message> {
        try self.validateAsInitial()
        return self
    }

    internal func validateAsInitialFatal(file: String = #filePath, line: UInt = #line) {
        switch self.underlying {
        case .same, .unhandled:
            fatalError("Illegal initial behavior! Attempted to spawn(\(self)) at \(file):\(line)")

        default:
            return
        }
    }

    /// Ensure that the behavior is in "canonical form", i.e. that all setup behaviors are reduced (run)
    /// before storing the behavior. This process may trigger executing setup(onStart) behaviors.
    ///
    /// Warning: Remember that a first start (or re-start) of a behavior must be triggered using `Behavior.start`
    ///          rather than just canonicalize since we want to recursively trigger
    ///
    /// - Throws: `IllegalBehaviorError.tooDeeplyNestedBehavior` when a too deeply nested behavior is found,
    ///           in order to avoid attempting to start an possibly infinitely deferred behavior.
    internal func canonicalize(_ context: ActorContext<Message>, next: Behavior<Message>) throws -> Behavior<Message> {
        guard self.isStillAlive else {
            return self  // ignore, we're already dead and cannot become any other behavior
        }
        return try canonicalizeLive(context, next: next)
    }

    private func canonicalizeLive(
        _ context: ActorContext<Message>,
        next: Behavior<Message>
    ) throws -> Behavior<Message> {
        // Note: on purpose not implemented as tail recursive function since tail-call elimination is not guaranteed
        let failAtDepth: Int = context.system.settings.actor.maxBehaviorNestingDepth

        // what if already stopped or failed
        func reduce(_ base: Behavior<Message>, _ next: Behavior<Message>, _ depth: Int) throws -> Behavior<Message> {
            let deeper: Int = depth + 1
            guard depth < failAtDepth else {
                throw IllegalBehaviorError.tooDeeplyNestedBehavior(reached: next, depth: depth)
            }
            var canonical: Behavior<Message> = next
            while true {
                switch canonical.underlying {
                case let .setup(onStart):
                    canonical = try onStart(context)

                case .same where self.isSetup:
                    throw IllegalBehaviorError.illegalTransition(from: self, target: next)

                case .same, .ignore, .unhandled:
                    return base

                case let .stop(.none, reason):
                    return .stop(reason: reason, postStop: base)

                case let .orElse(first, second):
                    return try canonicalizeAlternatives(
                        first: first,
                        second: second,
                        base: canonical,
                        depth: deeper,
                        reduce: reduce
                    )

                case let .intercept(inner, interceptor):
                    let innerCanonicalized: Behavior<Message> = try reduce(inner, .same, deeper)
                    return .intercept(behavior: innerCanonicalized, with: interceptor)

                case let .signalHandling(onMessage, onSignal):
                    return .signalHandling(
                        handleMessage: try reduce(canonical, onMessage, deeper),
                        handleSignal: onSignal
                    )

                case let .signalHandlingAsync(onMessage, onSignalAsync):
                    return .signalHandlingAsync(
                        handleMessage: try reduce(canonical, onMessage, deeper),
                        handleSignal: onSignalAsync
                    )

                case let .suspend(handler):
                    return .suspended(previousBehavior: base, handler: handler)

                case .stop(.some, _), .failed, .suspended, .receive, .receiveMessage,
                    .receiveAsync, .receiveMessageAsync:
                    return canonical
                }
            }
        }
        return try reduce(self, next, 0)
    }

    private func canonicalizeAlternatives(
        first: Behavior<Message>,
        second: Behavior<Message>,
        base: Behavior<Message>,
        depth: Int,
        reduce: (Behavior<Message>, Behavior<Message>, Int) throws -> Behavior<Message>
    ) rethrows -> Behavior<Message> {
        let canonicalFirst: Behavior<Message> = try reduce(base, first, depth)
        let canonicalSecond: Behavior<Message> = try reduce(base, second, depth)
        return canonicalFirst.orElse(canonicalSecond)
    }

    // make not recursive perhaps since could blow up on large chain?
    /// Starting a behavior means triggering all onStart actions of nested `.setup` calls.
    /// Interceptors are left in-place, and other behaviors remain unaffected.
    ///
    /// - Throws: `IllegalBehaviorError.tooDeeplyNestedBehavior` when a too deeply nested behavior is found,
    ///           in order to avoid attempting to start an possibly infinitely deferred behavior.
    internal func start(context: ActorContext<Message>) throws -> Behavior<Message> {
        let failAtDepth: Int = context.system.settings.actor.maxBehaviorNestingDepth

        func start0(_ behavior: Behavior<Message>, depth: Int) throws -> Behavior<Message> {
            guard depth < failAtDepth else {
                throw IllegalBehaviorError.tooDeeplyNestedBehavior(reached: behavior, depth: depth)
            }

            // Note: DO NOT use `default:`, we always want to explicitly know when we add a behavior and add specific
            // handling here.
            switch behavior.underlying {
            case let .intercept(inner, interceptor):
                // this should technically offload onto storage and then apply them again...
                return .intercept(behavior: try start0(inner, depth: depth + 1), with: interceptor)

            case let .setup(onStart):
                let started: Behavior<Message> = try onStart(context)
                return try start0(started, depth: depth + 1)

            case let .signalHandling(onMessageBehavior, onSignal):
                return .signalHandling(
                    handleMessage: try start0(onMessageBehavior, depth: depth + 1),
                    handleSignal: onSignal
                )

            case let .orElse(main, fallback):
                return try start0(main, depth: depth + 1)
                    .orElse(start0(fallback, depth: depth + 1))

            case let .suspended(previousBehavior, _):
                return try start0(previousBehavior, depth: depth + 1)

            default:  // remove the use of default: it is the devil </3
                return behavior
            }
        }

        return try start0(self, depth: 0)
    }

    /// Looks for a behavior in the stack that returns `true` for the passed in predicate.
    ///
    /// - Parameter predicate: used to check if any behavior in the stack has a specific property
    /// - Returns: `true` if a behavior exists that matches the predicate, `false` otherwise
    internal func existsInStack(_ predicate: (Behavior<Message>) -> Bool) -> Bool {
        if predicate(self) {
            return true
        }

        switch self.underlying {
        case let .intercept(behavior, _):
            return behavior.existsInStack(predicate)

        case let .orElse(first, second):
            return first.existsInStack(predicate) || second.existsInStack(predicate)

        case let .stop(.some(postStop), _):
            return postStop.existsInStack(predicate)

        default:
            return false
        }
    }
}
