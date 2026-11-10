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

import Logging

/// Handles failures that may occur during message (or signal) handling within an actor.
///
/// Currently not for user extension.
internal class Supervisor<Message: Codable> {
    internal typealias Directive = SupervisionDirective<Message>

    internal var descriptionForLogs: String {
        "\(type(of: self))"
    }

    internal final func interpretSupervised(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        message: Message
    ) throws -> Behavior<Message> {
        traceLog_Supervision("CALL WITH \(target) @@@@ [\(message)]:\(type(of: message))")
        return try self.interpretSupervised0(target: target, context: context, processingAction: .message(message))
    }

    internal final func interpretSupervised(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        signal: Signal
    ) throws -> Behavior<Message> {
        traceLog_Supervision("INTERCEPT SIGNAL APPLY: \(target) @@@@ \(signal)")
        return try self.interpretSupervised0(target: target, context: context, processingAction: .signal(signal))
    }

    internal final func interpretSupervised(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        closure: ActorClosureCarry
    ) throws -> Behavior<Message> {
        traceLog_Supervision("CALLING CLOSURE: \(target)")
        return try self.interpretSupervised0(target: target, context: context, processingAction: .closure(closure))
    }

    internal final func interpretSupervised(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        subMessage: SubMessageCarry
    ) throws -> Behavior<Message> {
        traceLog_Supervision("INTERPRETING SUB MESSAGE: \(target)")
        return try self.interpretSupervised0(
            target: target,
            context: context,
            processingAction: .subMessage(subMessage)
        )
    }

    internal final func interpretSupervised(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        closure: @escaping () throws -> Behavior<Message>
    ) throws -> Behavior<Message> {
        traceLog_Supervision("CALLING CLOSURE: \(target)")
        return try self.interpretSupervised0(
            target: target,
            context: context,
            processingAction: .continuation(closure)
        )
    }

    internal final func startSupervised(
        target: Behavior<Message>,
        context: ActorContext<Message>
    ) throws -> Behavior<Message> {
        traceLog_Supervision("CALLING START")
        return try self.interpretSupervised0(
            target: target,
            context: context,
            processingAction: .start
        )
    }

    /// Implements all directives, which supervisor implementations may yield to instruct how we should (if at
    /// all) restart an actor.
    @inline(__always)
    internal final func interpretSupervised0(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        processingAction: ProcessingAction<Message>
    ) throws -> Behavior<Message> {
        try self.interpretSupervised0(
            target: target,
            context: context,
            processingAction: processingAction,
            nFoldFailureDepth: 1
        )  // 1 since we already have "one failure"
    }

    @inline(__always)
    internal final func interpretSupervised0(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        processingAction: ProcessingAction<Message>,
        nFoldFailureDepth _: Int
    ) throws -> Behavior<Message> {
        do {
            switch processingAction {
            case .start:
                return try target.start(context: context)

            case .message(let message):
                return try target.interpretMessage(context: context, message: message)

            case .signal(let signal):
                return try target.interpretSignal(context: context, signal: signal)

            case .closure(let closure):
                try closure.function()
                return .same

            case .continuation(let continuation):
                return try continuation()

            case .subMessage(let carry):
                guard let subFunction = context.subReceive(identifiedBy: carry.identifier) else {
                    fatalError(
                        """
                        BUG! Received sub message [\(carry.message)]:\(type(of: carry.message)) for unknown \
                        identifier \(carry.identifier) on address \(carry.subReceiveAddress). Please report \
                        this on the issue tracker.
                        """
                    )
                }

                return try subFunction(carry)
            }
        } catch {
            return try self.handleError(
                context: context,
                target: target,
                processingAction: processingAction,
                error: error
            )
        }
    }

    @usableFromInline
    internal func handleError(
        context: ActorContext<Message>,
        target: Behavior<Message>,
        processingAction: ProcessingAction<Message>,
        error: Error
    ) throws -> Behavior<Message> {
        var cause: Error = error
        let kind: ProcessingType = processingAction.type
        // The following restart loop exists to support interpreting `PreRestart` and `Start` signal
        // interpretation failures;
        // If the actor fails during restarting, this failure becomes the new failure reason, and we
        // supervise this failure
        // this allows "try again a few times restarts" to happen even if the fault occurs in starting the
        // actor (e.g. opening a file or obtaining some resource failing).
        //
        // This "restart loop" matters only for:
        // - `.restartImmediately` decisions which result in throwing during `restartPrepare` OR `restartComplete`,
        // - or `.restartDelayed` decisions which result in throwing during `restartPrepare`.
        //
        // Since this is a special situation somewhat, in which the tight crash loop could consume
        // considerable resources (and maybe never recover),
        // we limit the number of times the restart is attempted

        repeat {
            switch processingAction {
            case .closure(let closure):
                context.log.warning(
                    """
                    Actor has THROWN [\(cause)]:\(type(of: cause)) while interpreting \
                    [closure defined at \(closure.file):\(closure.line)], handling with \(self.descriptionForLogs)
                    """
                )

            default:
                context.log.warning(
                    """
                    Actor has THROWN [\(cause)]:\(type(of: cause)) while interpreting \
                    \(processingAction), handling with \(self.descriptionForLogs)
                    """
                )
            }

            let directive: Directive
            do {
                directive = try handleFailure(context, target: target, failure: .error(cause), processingType: kind)
            } catch {
                // An error was thrown by our Supervisor logic while handling the failure, this is
                // a bug and thus we crash hard
                throw Supervision.SupervisionError.illegalDecision(
                    "Illegal supervision decision detected.",
                    handledError: cause,
                    error: error
                )
            }

            do {
                switch directive {
                case .stop:
                    return .stop(reason: .failure(.error(error)))

                case .escalate(let failure):
                    return context.downcastUnsafe.escalate(failure: failure)

                case .restartImmediately(let replacement):
                    try context.downcastUnsafe.restartPrepare()
                    return try context.downcastUnsafe.restartComplete(with: replacement)

                case let .restartDelayed(delay, replacement):
                    try context.downcastUnsafe.restartPrepare()
                    return SupervisionRestartDelayedBehavior.after(delay: delay, with: replacement)
                }
            } catch {
                // A failure during restart becomes the failure passed to the supervisor.
                cause = error
                continue
            }
        } while true  // Ends when a directive succeeds or the supervisor gives up.
    }

    // MARK: Internal Supervisor API

    /// Handle a fault that happened during processing.
    ///
    /// The returned `SupervisionDirective` will be interpreted appropriately.
    internal func handleFailure(
        _: ActorContext<Message>,
        target _: Behavior<Message>,
        failure _: Supervision.Failure,
        processingType _: ProcessingType
    ) throws -> SupervisionDirective<Message> {
        undefined()
    }

    /// Implement and return `true` if this supervisor can handle the failure or not.
    /// If `false` is returned and other supervisors are present, they will be tied in order, until a supervisor which
    /// can handle the failure is found, or if no such supervisor exists the failure will cause the actor to
    /// crash (as expected).
    internal func canHandle(failure _: Supervision.Failure) -> Bool {
        undefined()
    }

    /// Invoked when wrapping (with this `Supervisor`) a `Behavior` that already is supervised.
    ///
    /// The method is always invoked _on_ the existing supervisor with the "new" supervisor.
    /// If this method returns `true` the new supervisor will be dropped and no wrapping will be performed.
    internal func isSame(as _: Supervisor<Message>) -> Bool {
        undefined()
    }
}
