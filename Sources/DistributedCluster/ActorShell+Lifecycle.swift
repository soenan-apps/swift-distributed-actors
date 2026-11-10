// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO

extension ActorShell {
    @usableFromInline internal var deathWatch: DeathWatchImpl<Message> {
        get {
            guard let watchState = self.deathWatchState else {
                fatalError("BUG! Tried to access deathWatch on \(self.id) after it was cleared.")
            }
            return watchState
        }
        _modify {
            guard var watchState = self.deathWatchState else {
                fatalError("BUG! Tried to access deathWatch on \(self.id) after it was cleared.")
            }
            self.deathWatchState = nil
            defer { self.deathWatchState = watchState }
            yield &watchState
        }
    }

    /// INTERNAL API: MUST be called immediately after constructing the cell and ref,
    /// as the actor needs to access its ref from its context during setup or other behavior reductions
    internal func set(ref: ActorCell<Message>) {
        self.actorCell = ref  // atomic?
    }

    internal func escalate(failure: Supervision.Failure) -> Behavior<Message> {
        self.behavior = self.behavior.fail(cause: failure)

        return self.behavior
    }

    /// Similar to `fail` however assumes that the current mailbox run will never complete, which can happen when we
    /// crashed,
    /// and invoke this function from a signal handler.
    public func reportCrashFail(cause: MessageProcessingFailure) {
        // if supervision or configurations or failure domain dictates something else will happen, explain
        // it to the user here
        let crashHandlingExplanation: String = "Terminating actor, process and thread remain alive."

        self.log.error("Actor crashing, reason: [\(cause)]:\(type(of: cause)). \(crashHandlingExplanation)")

        self.behavior = self.behavior.fail(cause: .fault(cause))
    }

    /// Used by supervision, from failure recovery.
    /// In such case the cell must be restarted while the mailbox remain in-tact.
    ///
    /// - Warning: This call MAY throw if user code would throw in reaction to interpreting `PreRestart`;
    ///            If this happens the actor MUST be terminated immediately as we suspect things went very bad™ somehow.
    @inlinable
    public func restartPrepare() throws {
        self.children.stopAll(includeAdapters: false)
        self.timers.cancelAll()  // cancel all except the restart timer

        // Yes, we ignore the behavior returned by pre-restart on purpose, the supervisor decided what we
        // should `become`,
        // and we can not change this decision; at least not in the current scheme (which is simple and good enough for
        // most cases).
        _ = try self.behavior.interpretSignal(context: self, signal: Signals.PreRestart())

        // NOT interpreting Start yet, as it may have to be done after a delay
    }

    /// Used by supervision.
    /// MUST be preceded by an invocation of `restartPrepare`.
    /// The two steps MAY be performed in different point in time; reason being: backoff restarts,
    /// which need to suspend the actor, and NOT start it just yet, until the system message awakens it again.
    public func restartComplete(with behavior: Behavior<Message>) throws -> Behavior<Message> {
        try behavior.validateAsInitial()
        self.behavior = behavior
        try self.interpretStart()
        return self.behavior
    }

    /// Encapsulates logic that has to always be triggered on a state transition to specific behaviors
    /// Always invoke `becomeNext` rather than assigning to `self.behavior` manually.
    ///
    /// Returns: `true` if next behavior is .stop and appropriate actions will be taken
    internal func becomeNext(behavior next: Behavior<Message>) throws {
        // handling "unhandled" would be good here... though I think type wise this won't fly, since we
        // care about signal too
        self.behavior = try self.behavior.canonicalize(self, next: next)
    }

    internal func interpretStart() throws {
        // start means we need to evaluate all `setup` blocks, since they need to be triggered eagerly
        traceLog_Cell("START with behavior: \(self.behavior)")

        let started: Behavior<Message> = try self.supervisor.startSupervised(target: self.behavior, context: self)
        try self.becomeNext(behavior: started)
    }

    /// Interpret a `resume` with the passed in result, potentially waking up the actor from `suspended` state.
    /// Interpreting a resume NOT in suspended state is an error and should never happen.
    internal func interpretResume(_ result: Result<Any, Error>) throws -> ActorRunResult {
        switch self.behavior.underlying {
        case let .suspended(previousBehavior, handler):
            let next: Behavior<Message> = try self.supervisor.interpretSupervised(
                target: previousBehavior, context: self
            ) {
                try handler(result)
            }
            // We need to ensure the behavior is canonicalized, as perhaps the suspension was wrapping setup or similar
            let canonicalizedNext: Behavior<Message> = try previousBehavior.canonicalize(self, next: next)
            return try self.finishInterpretAnyMessage(canonicalizedNext)

        default:
            self.log.error(
                "Received .resume message while being in non-suspended state. Please report this as a bug.",
                metadata: [
                    "result": "\(result)",
                    "behavior": "\(self.behavior)",
                ]
            )
            return self.runState
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Lifecycle and DeathWatch interactions

    /// This is the final method an ActorCell ever runs.
    ///
    /// It notifies any remaining watchers about its termination, releases any remaining resources,
    /// and clears its behavior, allowing state kept inside it to be released as well.
    ///
    /// Once this method returns the cell becomes "terminated", an empty shell, and may never be run again.
    /// This is coordinated with its mailbox, which by then becomes closed, and shall no more accept any messages, not
    /// even system ones.
    ///
    /// Any remaining system messages are to be drained to deadLetters by the mailbox in its current run.
    internal func finishTerminating() -> ActorRunResult {
        self.actorCell.mailbox.setClosed()

        let myAddress: ActorID? = self.actorCell.id
        traceLog_Cell("FINISH TERMINATING \(self)")

        // stop all children? depends which style we'll end up with...
        // the thing is, I think we can express the entire "wait for children to stop" as a behavior, and no need to
        // make it special implementation in the cell

        // when terminating, we need to stop all timers, including system timers
        self.timers.cancelAll(includeSystemTimers: true)

        // notifying parent and other watchers has no ordering guarantees with regards to reception,
        // however let's first notify the parent and then all other watchers (even if parent did watch this child
        // we do not need to send it another terminated message, the terminatedChild is enough).
        //
        // note that even though the parent can (and often does) `watch(child)`, we filter it out from
        // our `watchedBy` set, since otherwise we would have to filter it out when sending the terminated back.
        // correctness is ensured though, since the parent always receives the `_ChildTerminated`.
        self.notifyParentOfTermination()
        self.notifyWatchersOfTermination()

        do {
            _ = try self.behavior.interpretSignal(context: self, signal: Signals.PostStop())
        } catch {
            // should probably .escalate instead;
            self.log.error("Exception in postStop. Supervision will NOT be applied. Error \(error)")
        }

        // validate all the niling out; can we null out the cell itself?
        self.deathWatchState = nil
        self.messageAdapters = []
        self.subReceives = [:]

        // become stopped, if not already
        switch self.behavior.underlying {
        case .failed(_, let failure):
            self.behavior = .stop(reason: .failure(failure))

        case .stop(_, let reason):
            self.behavior = .stop(reason: reason)

        default:
            self.behavior = .stop
        }

        traceLog_Cell("""
            CLOSED DEAD: \(String(describing: myAddress)) has completely terminated, and will \
            never act again.
            """)

        // It shall act, ah, nevermore!
        return .closed
    }

    // Implementation note: bridge method so Mailbox can call this when needed
    internal func notifyWatchersOfTermination() {
        traceLog_DeathWatch("NOTIFY WATCHERS WE ARE DEAD self: \(self.id)")
        self.deathWatch.notifyWatchersWeDied(myself: self.myself)
    }

    internal func notifyParentOfTermination() {
        let parent: AddressableActorRef = self.parentRef
        traceLog_DeathWatch(
            "NOTIFY PARENT WE ARE DEAD, myself: [\(self.id)], parent [\(parent.id)]"
        )

        guard case .failed(_, let failure) = self.behavior.underlying else {
            // we are not failed, so no need to further check for .escalate supervision
            return parent.sendSystemMessage(
                .childTerminated(ref: self.myself.asAddressable, .stopped)
            )
        }

        guard self.supervisor is EscalatingSupervisor<Message> else {
            // NOT escalating
            return parent.sendSystemMessage(
                .childTerminated(ref: self.myself.asAddressable, .failed(failure))
            )
        }

        parent.sendSystemMessage(
            .childTerminated(ref: self.myself.asAddressable, .escalating(failure))
        )
    }
}
