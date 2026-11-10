// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Internal system message / signal handling functions

extension ActorShell {
    internal func interpretSystemWatch(watcher: AddressableActorRef) {
        if self.behavior.isStillAlive {
            self.deathWatch.becomeWatchedBy(watcher: watcher, myself: self.myself, parent: self.parentRef)
        } else {
            // so we are in the middle of terminating already anyway
            watcher.sendSystemMessage(
                .terminated(ref: self.asAddressable, existenceConfirmed: true)
            )
        }
    }

    @inlinable
    internal func interpretSystemUnwatch(watcher: AddressableActorRef) {
        self.deathWatch.removeWatchedBy(watcher: watcher, myself: self.myself)
    }

    /// Interpret incoming .terminated system message
    ///
    /// Mutates actor cell behavior.
    /// May cause actor to terminate upon error or returning .stop etc from `.signalHandling` user code.
    internal func interpretTerminatedSignal(who dead: ActorID, terminated: Signals.Terminated) throws {
        #if SACT_TRACE_ACTOR_SHELL
        self.log.info("Received terminated: \(dead)")
        #endif

        let terminatedDirective: DeathWatchImpl<Message>.TerminatedMessageDirective =
            self.deathWatch.receiveTerminated(terminated)

        let next: Behavior<Message>
        if self.props.distributedActor {
            next = try self.supervisor.interpretSupervised(target: self.behavior, context: self, signal: terminated)
        } else {
            switch terminatedDirective {
            case .wasNotWatched:
                // it is not an actor we currently watch, thus we should not take actions nor
                // deliver the signal to the user
                self.log.trace(
                    """
                    Actor not known to [\(self.path)], but [\(terminated)] received for it. This may mean we \
                    received node terminated earlier, \
                    and already have removed the actor from our death watch.
                    """
                )
                return

            case .signal:
                next = try self.supervisor.interpretSupervised(target: self.behavior, context: self, signal: terminated)

            case .customMessage(let customTerminatedMessage):
                next = try self.supervisor.interpretSupervised(
                    target: self.behavior, context: self, message: customTerminatedMessage
                )
            }
        }

        switch next.underlying {
        case .unhandled:
            throw DeathPactError.unhandledDeathPact(
                dead,
                myself: self.myself.asAddressable,
                message: """
                    DeathPactError: Unhandled [\(terminated)] signal about watched actor [\(dead)]. \
                    Handle the `.terminated` signal in `.receiveSignal()` in order react to this \
                    situation differently than termination.
                    """
            )

        default:
            try self.becomeNext(behavior: next)  // make sure we don't drop the behavior...?
        }
    }

    /// Interpret incoming .nodeTerminated system message.
    ///
    /// Results in signaling `Terminated` for all of the locally watched actors on the (now terminated) node.
    /// This action is performed concurrently by all actors who have watched remote actors on given node,
    /// and no ordering guarantees are made about which actors will get the Terminated signals first.
    @inlinable
    internal func interpretNodeTerminated(_ terminatedNode: Cluster.Node) {
        #if SACT_TRACE_ACTOR_SHELL
        self.log.info("Received address terminated: \(terminatedNode)")
        #endif

        self.deathWatch.receiveNodeTerminated(terminatedNode, myself: self.asAddressable)
    }

    /// Interpret a carried signal directly -- those are potentially delivered by plugins or custom transports.
    /// They MAY share semantics with `Signals.Terminated`, in which case they would be interpreted accordingly.
    internal func interpretCarrySignal(_ signal: Signal) throws {
        #if SACT_TRACE_ACTOR_SHELL
        self.log.info("Received carried signal: \(signal)")
        #endif

        if let terminated = signal as? Signals.Terminated {
            // it is a Terminated sub-class, and thus shares semantics with it.
            try self.interpretTerminatedSignal(who: terminated.id, terminated: terminated)
        } else {
            let next: Behavior<Message> = try self.supervisor.interpretSupervised(
            target: self.behavior, context: self, signal: signal
        )
            try self.becomeNext(behavior: next)
        }
    }

    internal func interpretStop() throws {
        self.children.stopAll()
        try self.becomeNext(behavior: .stop(reason: .stopByParent))
    }

    internal func interpretChildTerminatedSignal(
        who terminatedRef: AddressableActorRef,
        terminated: Signals.ChildTerminated
    ) throws {
        #if SACT_TRACE_ACTOR_SHELL
        self.log.info("Received \(terminated)")
        #endif

        // we always first need to remove the now terminated child from our children
        _ = self.children.removeChild(identifiedBy: terminatedRef.id)
        // Implementation notes:
        // Normally this does not happen, however it MAY occur when the parent actor (self)
        // immediately performed a `stop()` on the child, and thus removes it from its
        // children container immediately; The following termination notification would therefore
        // reach the parent in which the child was already removed.

        // next we may apply normal deathWatch logic if the child was being watched
        if self.deathWatch.isWatching(terminatedRef.id) {
            return try self.interpretTerminatedSignal(who: terminatedRef.id, terminated: terminated)
        }
        // otherwise we deliver the message, however we do not terminate ourselves if it remains unhandled

        let next: Behavior<Message>
        if case .signalHandling = self.behavior.underlying {
            // we always want to call "through" the supervisor, make it more obvious that that should be the case
            // internal API wise?
            next = try self.supervisor.interpretSupervised(target: self.behavior, context: self, signal: terminated)
        } else {
            switch terminated.escalation {
            case .some(let failure):
                // the child actor decided to `.escalate` the error and thus we are notified about it
                // escalation differs from plain termination that by default it DOES cause us to crash as well,
                // causing a chain reaction of crashing until someone handles or the guardian
                // receives it and shuts down the system.
                self.log.warning("""
                    Failure escalated by [\(terminatedRef.path)] reached non-watching, non-signal \
                    handling parent, escalation will continue! Failure was: \(failure)
                    """)

                next = try self.supervisor.interpretSupervised(
                    target: .signalHandling(
                        handleMessage: self.behavior
                    ) { _, _ in
                        switch failure {
                        case .error(let error):
                            throw error

                        case .fault(let errorRepr):
                            throw errorRepr
                        }
                    },
                    context: self,
                    signal: terminated
                )

            case .none:
                // the child actor has stopped without providing us with a reason // ; does this
                // need to carry manual stop as a reason?
                //
                // no signal handling installed is semantically equivalent to unhandled
                next = Behavior<Message>.unhandled
            }
        }

        try self.becomeNext(behavior: next)
    }
}
