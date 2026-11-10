// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

// Offers the capability to interpret messages and signals.
extension Behavior {
    private enum MessageInterpretationFailure: String {
        case ignore = """
            Illegal attempt to interpret message with .ignore behavior! \
            Behavior should have been canonicalized before interpreting; This is a bug, please open a ticket.
            """
        case same = """
            Illegal attempt to interpret message with .same behavior! \
            Behavior should have been canonicalized. This is a bug, please open a ticket.
            """
        case suspend = """
            Illegal to attempt to interpret message with .suspend behavior! \
            Behavior should have been canonicalized. This is a bug, please open a ticket.
            """
        case unhandled = """
            Illegal attempt to interpret message with .unhandled behavior! \
            Behavior should have been canonicalized before interpreting; This is a bug, please open a ticket.
            """
    }

    // Implementation note: We don't do so here automatically in order to keep interpretations transparent and testable.
    /// Interpret the passed in message.
    ///
    /// Note: The returned behavior MUST be `Behavior.canonicalize`-ed in the vast majority of cases.
    public func interpretMessage(
        context: ActorContext<Message>,
        message: Message,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Behavior<Message> {
        switch self.underlying {
        case let .receiveMessage(recv):
            return try recv(message)

        case let .receiveMessageAsync(recv):
            return self.receiveMessageAsync(recv, message)

        case let .receive(recv):
            return try recv(context, message)

        case let .receiveAsync(recv):
            return self.receiveAsync(recv, message)

        case let .signalHandling(recvMsg, _):
            return try recvMsg.interpretMessage(context: context, message: message)

        case let .signalHandlingAsync(recvMsg, _):
            return try recvMsg.interpretMessage(context: context, message: message)

        case let .intercept(inner, interceptor):
            return try Interceptor.handleMessage(
                context: context,
                behavior: inner,
                interceptor: interceptor,
                message: message
            )

        case let .orElse(first, second):
            return try self.interpretOrElse(
                context: context,
                first: first,
                orElse: second,
                message: message,
                file: file,
                line: line
            )

        // illegal to attempt interpreting at the following behaviors (e.g. should have been canonicalized before):
        case .same:
            fatalError(MessageInterpretationFailure.same.rawValue, file: file, line: line)

        case .ignore:
            fatalError(MessageInterpretationFailure.ignore.rawValue, file: file, line: line)

        case .unhandled:
            fatalError(MessageInterpretationFailure.unhandled.rawValue, file: file, line: line)

        case .setup:
            rejectSetupMessage(context: context, message: message, file: file, line: line)

        case .stop:
            return .unhandled

        case .failed:
            return .unhandled

        case .suspend:
            fatalError(MessageInterpretationFailure.suspend.rawValue, file: file, line: line)

        case .suspended:
            rejectSuspendedMessage(context: context, message: message, file: file, line: line)
        }
    }

    private func rejectSetupMessage(
        context: ActorContext<Message>,
        message: Message,
        file: StaticString,
        line: UInt
    ) -> Never {
        fatalErrorBacktrace(
            """
            Illegal attempt to interpret message with .setup behavior! \
            Behaviors MUST be canonicalized before interpreting. This is a bug, please open a ticket.
              System: \(context.system)
              Address: \(context.id.detailedDescription)
              Message: \(message): \(type(of: message))
              Behavior: \(self)
            """,
            file: file,
            line: line
        )
    }

    private func rejectSuspendedMessage(
        context: ActorContext<Message>,
        message: Message,
        file: StaticString,
        line: UInt
    ) -> Never {
        fatalError(
            """
            No message should ever be delivered to a .suspended behavior!
              Message: \(message)
              Actor: \(context)
              This is a bug, please open a ticket.
            """,
            file: file,
            line: line
        )
    }

    /// Attempts interpreting signal using the current behavior, or returns `Behavior.unhandled` if no
    /// `Behavior.signalHandling` was found.
    public func interpretSignal(context: ActorContext<Message>, signal: Signal) throws -> Behavior<Message> {
        // This switch does not use a `default:` clause on purpose!
        // Each new behavior case must explicitly decide how to interpret signals.
        switch self.underlying {
        case let .stop(postStop, reason):
            if let postStop = postStop {
                return try .stop(
                    reason: reason,
                    postStop: postStop.interpretSignal(context: context, signal: signal)
                )
            }
            return .same

        case let .failed(behavior, cause):
            return try Behavior(
                underlying: .failed(behavior: behavior.interpretSignal(context: context, signal: signal), cause: cause)
            )

        case let .signalHandling(_, handleSignal):
            return try handleSignal(context, signal)

        case let .signalHandlingAsync(_, receiveSignalAsync):
            return self.receiveSignalAsync(context: context, signal: signal, handleSignal: receiveSignalAsync)

        case let .orElse(first, second):
            let maybeHandled: Behavior<Message> = try first.interpretSignal(context: context, signal: signal)
            if maybeHandled.isUnhandled {
                return try second.interpretSignal(context: context, signal: signal)
            }
            return maybeHandled

        case let .intercept(behavior, interceptor):
            return try interceptor.interceptSignal(target: behavior, context: context, signal: signal)

        case let .suspended(previous, handler):
            let nextBehavior: Behavior<Message> = try previous.interpretSignal(context: context, signal: signal)
            if nextBehavior.isTerminal {
                return nextBehavior
            }
            return try .suspended(
                previousBehavior: previous.canonicalize(context, next: nextBehavior),
                handler: handler
            )

        case .receiveMessage, .receive:
            return .unhandled

        case .receiveMessageAsync, .receiveAsync:
            return .unhandled

        case .setup:
            return .unhandled

        case .same:
            return .unhandled

        case .ignore:
            return .unhandled

        case .unhandled:
            return .unhandled

        case .suspend:
            return .unhandled
        }
    }
}
