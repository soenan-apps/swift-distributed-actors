// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Interceptor {
    internal static func handleMessage(
        context: ActorContext<Message>,
        behavior: Behavior<Message>,
        interceptor: Interceptor<Message>,
        message: Message
    ) throws -> Behavior<Message> {
        let next: Behavior<Message> = try interceptor.interceptMessage(
            target: behavior, context: context, message: message
        )

        return try Self.deduplicate(context: context, behavior: next, interceptor: interceptor)
    }

    internal static func deduplicate(
        context: ActorContext<Message>,
        behavior: Behavior<Message>,
        interceptor: Interceptor<Message>
    ) throws -> Behavior<Message> {
        func deduplicate0(_ behavior: Behavior<Message>) -> Behavior<Message> {
            let hasDuplicatedIntercept: Bool = behavior.existsInStack { candidate in
                switch candidate.underlying {
                case let .intercept(_, otherInterceptor):
                    return interceptor.isSame(as: otherInterceptor)

                default:
                    return false
                }
            }

            if hasDuplicatedIntercept {
                return behavior
            }
            return .intercept(behavior: behavior, with: interceptor)
        }

        let started: Behavior<Message> = try behavior.start(context: context)

        if case let .stop(.some(postStop), reason) = started.underlying {
            return .stop(reason: reason, postStop: deduplicate0(postStop))
        }
        if started.isUnhandled || started.isSame || started.isTerminal || started.isSuspend {
            return started
        }
        return deduplicate0(started)
    }
}
