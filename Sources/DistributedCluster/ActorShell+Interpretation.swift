// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO

extension ActorShell {
    internal struct MessageAdapterClosure {
        /// The metatype of the expected incoming parameter; it will be cast and handled by the erased closure.
        ///
        /// We need to store the metatype, because we need `is` relationship to support adapters over classes
        internal let metaType: AnyMetaType
        internal let closure: (Any) -> Message?
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Interpreting messages

    internal var continueRunning: Bool {
        switch self.behavior.underlying {
        case .suspended:
            return false

        case .stop, .failed:
            return self.children.nonEmpty

        default:
            return true
        }
    }

    @usableFromInline internal var isSuspended: Bool {
        self.behavior.isSuspended
    }

    internal var runState: ActorRunResult {
        if self.continueRunning {
            return .continueRunning
        }
        if self.isSuspended {
            return .shouldSuspend
        }
        return .shouldStop
    }

    /// Interprets the incoming message using the current `Behavior` and swaps it with the
    /// next behavior (as returned by user code, which the message was applied to).
    ///
    /// Warning: Mutates the cell's behavior.
    /// Returns: `true` if the actor remains alive, and `false` if it now is becoming `.stop`
    internal func interpretMessage(message: Message) throws -> ActorRunResult {
        do {
            let next: Behavior<Message> = try self.supervisor.interpretSupervised(
            target: self.behavior, context: self, message: message
        )

            #if SACT_TRACE_ACTOR_SHELL
            self.log.info("Applied [\(message)]:\(type(of: message)), becoming: \(next)")
            #endif  // make the \next printout nice dont log messages (could leak pass etc)

            return try self.finishInterpretAnyMessage(next)
        } catch {
            throw error
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Handling system messages

    /// Process single system message and return if processing of further shall continue.
    /// If not, then they will be drained to deadLetters – as it means that the actor is terminating!
    ///
    /// Throws:
    ///   - user behavior thrown exceptions
    ///   - or `DeathPactError` when a watched actor terminated and the termination signal was not handled; See "death
    /// watch" for details.
    internal func interpretSystemMessage(message: SystemMessages) throws -> ActorRunResult {
        traceLog_Cell("Interpret system message: \(message)")

        switch message {
        case .start:
            try self.interpretStart()

        // death watch
        case .watch(_, let watcher):
            self.interpretSystemWatch(watcher: watcher)

        case .unwatch(_, let watcher):
            self.interpretSystemUnwatch(watcher: watcher)

        case let .terminated(ref, existenceConfirmed, nodeTerminated):
            let terminated: Signals.Terminated = Signals.Terminated(
                id: ref.id, existenceConfirmed: existenceConfirmed, nodeTerminated: nodeTerminated
            )
            try self.interpretTerminatedSignal(who: ref.id, terminated: terminated)

        case let .childTerminated(ref, circumstances):
            switch circumstances {
            // escalation takes precedence over death watch in terms of how we report errors
            case .escalating(let failure):
                // we only populate `escalation` if the child is escalating
                let terminated: Signals.ChildTerminated = Signals.ChildTerminated(id: ref.id, escalation: failure)
                try self.interpretChildTerminatedSignal(who: ref, terminated: terminated)

            case .stopped:
                let terminated: Signals.ChildTerminated = Signals.ChildTerminated(id: ref.id, escalation: nil)
                try self.interpretChildTerminatedSignal(who: ref, terminated: terminated)

            case .failed:
                let terminated: Signals.ChildTerminated = Signals.ChildTerminated(id: ref.id, escalation: nil)
                try self.interpretChildTerminatedSignal(who: ref, terminated: terminated)
            }

        case .nodeTerminated(let remoteNode):
            self.interpretNodeTerminated(remoteNode)

        case .carrySignal(let signal):
            try self.interpretCarrySignal(signal)

        case .stop:
            try self.interpretStop()

        case .resume(let result):
            return try self.interpretResume(result)

        case .tombstone:
            return self.finishTerminating()
        }

        return self.runState
    }

    internal func interpretClosure(_ closure: ActorClosureCarry) throws -> ActorRunResult {
        let next: Behavior<Message> = try self.supervisor.interpretSupervised(
            target: self.behavior, context: self, closure: closure
        )
        traceLog_Cell("Applied closure, becoming: \(next)")

        return try self.finishInterpretAnyMessage(next)
    }

    internal func interpretAdaptedMessage(_ carry: AdaptedMessageCarry) throws -> ActorRunResult {
        let maybeAdapter: MessageAdapterClosure? = self.messageAdapters.first { adapter in
            adapter.metaType.isInstance(carry.message)
        }

        guard let adapter = maybeAdapter?.closure else {
            self.log.warning(
                """
                    Received adapted message [\(carry.message)]:\(type(of: carry.message as Any)) for \
                    which no adapter was registered.
                    """,
                metadata: [
                    "actorRef/adapters": "\(self.messageAdapters)"
                ]
            )
            try self.becomeNext(behavior: .ignore)  // make .drop once implemented
            return self.runState
        }

        let next: Behavior<Message>
        if let adapted = adapter(carry.message) {
            next = try self.supervisor.interpretSupervised(target: self.behavior, context: self, message: adapted)
        } else {
            next = .unhandled  // could be .drop
        }
        traceLog_Cell("Applied adapted message \(carry.message), becoming: \(next)")

        return try self.finishInterpretAnyMessage(next)
    }

    internal func interpretSubMessage(_ subMessage: SubMessageCarry) throws -> ActorRunResult {
        let next: Behavior<Message> = try self.supervisor.interpretSupervised(
            target: self.behavior, context: self, subMessage: subMessage
        )
        traceLog_Cell("Applied subMessage \(subMessage.message), becoming: \(next)")

        return try self.finishInterpretAnyMessage(next)
    }

    /// Handles all actions that MUST be applied after a message is interpreted.
    @usableFromInline
    internal func finishInterpretAnyMessage(_ next: Behavior<Message>) throws -> ActorRunResult {
        if next.isChanging {
            try self.becomeNext(behavior: next)
        }

        if !self.behavior.isStillAlive {
            self.children.stopAll()
        }

        return self.runState
    }

    /// Fails the actor using the passed in error.
    ///
    /// May ONLY be invoked by the Mailbox.
    ///
    /// Special handling is applied to `DeathPactError` since if that error is passed in here, we know that
    /// `.terminated`
    /// was not handled and we have to adhere to the DeathPact contract by stopping this actor as well.
    ///
    /// We only FORCE the sending of a tombstone if we know we have parked the thread because an actual failure
    /// happened,
    /// thus this run *will never complete* and we have to make sure that we run the cleanup that the tombstone causes.
    /// This means that while the current thread is parked forever, we will enter the mailbox with another last run (!),
    /// to process the cleanups.
    @usableFromInline
    internal func fail(_ error: Error) {
        self.actorCell.mailbox.setFailed()
        self.behavior = self.behavior.fail(cause: .error(error))

        switch error {
        case DeathPactError.unhandledDeathPact(_, _, let message):
            self.log.error("\(message)")  // configurable logging? in props?

        default:
            self.log.warning("Actor threw error, reason: [\(error)]:\(type(of: error)). Terminating.")
        }
    }
}
