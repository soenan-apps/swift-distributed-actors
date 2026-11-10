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

import Atomics
import CoreMetrics
import DistributedActorsConcurrencyHelpers
import Logging

internal final class Mailbox<Message: Codable> {
    internal enum EnqueueDirective {
        case alreadyScheduled
        case mailboxClosed
        case mailboxFull
        case mailboxTerminating
        case needsScheduling
    }

    internal weak var shell: ActorShell<Message>?
    internal let atomicStatus: ManagedAtomic<UInt64> = .init(0)
    internal let userMessages: MPSCLinkedQueue<Payload>
    internal let systemMessages: MPSCLinkedQueue<SystemMessages>
    internal let capacity: UInt32
    internal let maxRunLength: UInt32
    internal let deadLetters: ActorRef<DeadLetter>
    internal let id: ActorID

    internal let measureMessages: Bool = true

    internal init(shell: ActorShell<Message>, maxRunLength: UInt32 = 100) {
        #if SACT_TESTS_LEAKS
        if shell.id.segments.first?.value == "user" {
            _ = shell.actorSystem?.userMailboxInitCounter.loadThenWrappingIncrement(ordering: .relaxed)
        }
        #endif
        self.shell = shell
        self.userMessages = MPSCLinkedQueue()
        self.systemMessages = MPSCLinkedQueue()
        self.capacity = .max
        self.maxRunLength = maxRunLength
        self.deadLetters = shell.system.deadLetters
        self.id = shell.actorID
    }

    /// **CAUTION**: For testing purposes only. Not safe to use for actually running actors.
    internal init(system: ClusterSystem, capacity: UInt32, maxRunLength: UInt32 = 100) {
        self.shell = nil
        self.userMessages = MPSCLinkedQueue()
        self.systemMessages = MPSCLinkedQueue()
        self.capacity = capacity
        self.maxRunLength = maxRunLength
        self.deadLetters = system.deadLetters
        self.id = system.deadLetters.id
    }

    @inlinable
    internal func sendMessage(envelope: Payload, file: String, line: UInt) {
        func sendAndDropAsDeadLetter() {
            self.deadLetters.tell(DeadLetter(envelope.payload, recipient: self.id, sentAtFile: file, sentAtLine: line))
        }

        switch self.enqueueUserMessage(envelope) {
        case .needsScheduling:
            traceLog_Mailbox(
                self.id.path,
                "Enqueued message \(envelope.payload), scheduling for execution",
                file: #fileID,
                line: #line
            )
            guard let shell = self.shell else {
                traceLog_Mailbox(
                    self.id.path,
                    "ActorShell was released! Unable to complete sendMessage, dropping: \(envelope)",
                    file: #fileID,
                    line: #line
                )
                self.deadLetters.tell(
                    DeadLetter(envelope.payload, recipient: self.id, sentAtFile: file, sentAtLine: line)
                )
                break
            }
            shell.messageDispatcher.execute(self.run)

        case .alreadyScheduled:
            traceLog_Mailbox(
                self.id.path,
                "Enqueued message \(envelope.payload), someone scheduled already",
                file: #fileID,
                line: #line
            )

        case .mailboxTerminating:
            // Enqueued messages are drained by the tombstone run before the mailbox closes.
            sendAndDropAsDeadLetter()

        case .mailboxClosed:
            traceLog_Mailbox(self.id.path, "is CLOSED, dropping message \(envelope)", file: #fileID, line: #line)
            sendAndDropAsDeadLetter()

        case .mailboxFull:
            traceLog_Mailbox(self.id.path, "is full, dropping message \(envelope)", file: #fileID, line: #line)
            sendAndDropAsDeadLetter()
        }
    }

    @inlinable
    internal func enqueueUserMessage(_ envelope: Payload) -> EnqueueDirective {
        traceLog_Mailbox(self.id.path, "INCREMENT MESSAGE COUNT", file: #fileID, line: #line)
        let oldStatus: Status = self.incrementMessageCount()
        guard oldStatus.messageCount < self.capacity else {
            // If we passed the maximum capacity of the user queue, we can't enqueue more
            // items and have to decrement the activations count again. This is not racy,
            // because we only process messages if the queue actually contains them (does
            // not return NULL), so even if messages get processed concurrently, it's safe
            // to decrement here.
            _ = self.decrementMessageCount()
            // The enqueue that reached capacity already reported the count.
            return .mailboxFull
        }

        guard !oldStatus.isTerminating else {
            _ = self.decrementMessageCount()
            // The enqueue that initiated termination already reported the count.
            return .mailboxTerminating
        }

        guard !oldStatus.isClosed else {
            _ = self.decrementMessageCount()
            // Closing occurs on a final run, which already updates the count.
            return .mailboxClosed
        }

        // If the mailbox is not full, we insert it into the queue and return,
        // whether this was the first activation, to signal the need to enqueue
        // this mailbox.
        self.userMessages.enqueue(envelope)
        self.shell?.metrics[gauge: .mailboxCount]?.record(oldStatus.messageCount + 1)

        if oldStatus.activations == 0, !oldStatus.isSuspended {
            return .needsScheduling
        }
        return .alreadyScheduled
    }

    /// Enqueues `.start` but does NOT activate the actor. Used for LazyStart and MUST be called as
    /// the first thing before the ref is exposed, thus the status MUST be 0, as noone else should have had
    /// any chance to interact with this mailbox yet
    @inlinable
    internal func enqueueStart() {
        let oldStatus: Status = self.setHasSystemMessages()
        guard oldStatus.activations == 0 else {
            fatalError("!!! BUG !!! Status was \(oldStatus), expected 0.")
        }
        self.systemMessages.enqueue(.start)
    }

    @inlinable
    internal func schedule() {
        guard let shell = self.shell else {
            traceLog_Mailbox(
                self.id.path,
                "has already released the actor cell, ignoring scheduling attempt",
                file: #fileID,
                line: #line
            )
            return
        }
        shell.messageDispatcher.execute(self.run)
    }

    @inlinable
    internal func sendSystemMessage(_ systemMessage: SystemMessages, file: String, line: UInt) {
        func sendAndDropAsDeadLetter() {
            self.deadLetters.tell(
                DeadLetter(systemMessage, recipient: self.id, sentAtFile: file, sentAtLine: line),
                file: file,
                line: line
            )
        }

        switch self.enqueueSystemMessage(systemMessage) {
        case .needsScheduling:
            self.scheduleSystemMessage(systemMessage)

        case .alreadyScheduled:
            traceLog_Mailbox(
                self.id.path,
                "Enqueued system message \(systemMessage), someone scheduled already",
                file: #fileID,
                line: #line
            )

        case .mailboxTerminating:
            traceLog_Mailbox(
                self.id.path,
                "Mailbox is terminating. This sendSystemMessage MUST be send to dead letters. "
                    + "System Message: \(systemMessage)",
                file: #fileID,
                line: #line
            )
            sendAndDropAsDeadLetter()

        case .mailboxClosed:
            // not enqueued, mailbox is closed; it cannot and will not interact with any more messages.
            //
            // it is crucial for correctness of death watch that we drain messages to dead letters,
            // which in turn is able to handle watch() automatically for us there;
            // knowing that the watch() was sent to a terminating or dead actor.
            traceLog_Mailbox(
                self.id.path,
                "Dead letter: \(systemMessage), since mailbox is CLOSED",
                file: #fileID,
                line: #line
            )
            sendAndDropAsDeadLetter()

        case .mailboxFull:
            fatalError(
                "Dropped system message because mailbox is full. "
                    + "This should never happen and is a mailbox bug, please report an issue."
            )
        }
    }

    @usableFromInline
    internal func scheduleSystemMessage(_ systemMessage: SystemMessages) {
        traceLog_Mailbox(
            self.id.path,
            "Enqueued system message \(systemMessage), scheduling for execution",
            file: #fileID,
            line: #line
        )
        guard let shell = self.shell else {
            self.deadLetters.tell(DeadLetter(systemMessage, recipient: nil))
            traceLog_Mailbox(
                self.id.path,
                "has already released the actor cell, dropping system message \(systemMessage)",
                file: #fileID,
                line: #line
            )
            return
        }
        shell.messageDispatcher.execute(self.run)
    }

    private func enqueueSystemMessage(_ systemMessage: SystemMessages) -> EnqueueDirective {
        // The ordering of enqueue/activate calls is tremendously important here and MUST NOT be inversed.
        //
        // Unlike user messages, where the message count is stored, here we first enqueue and then activate.
        // This MAY result in an enqueue into a terminating or even closed mailbox.
        // This is only during the period of time between terminating->closed->cell-released however.
        //
        // We can enqueue "too much", and elements remain in the queue until we get deallocated.
        //
        // Note: The problem with `activate then enqueue` is that it allows for the following race condition to happen:
        //   A0: is processing messages; before ending a run we see if any more system messages are to be processed
        //   (A1 attempts sending message to A0)
        //   A1: send_system_message, try_activate succeeds
        //   A0: notices, that there's more system messages to run, so attempts to do so
        //   !!: A1 did not yet enqueue the system message
        //   A0: falls of a cliff, does not process the system message
        //   A1: enqueues the system message and
        //
        // The status can change between enqueue and activation. The activation result still routes
        // the message to dead letters, though the queued copy may remain until cell deallocation.
        self.systemMessages.enqueue(systemMessage)

        let oldStatus: Status = self.setHasSystemMessages()

        if oldStatus.isTerminating {
            return .mailboxTerminating
        }
        if oldStatus.isClosed {
            return .mailboxClosed
        }
        if oldStatus.activations == 0 {
            return .needsScheduling
        }
        if !oldStatus.hasSystemMessages, !oldStatus.isProcessingSystemMessages, oldStatus.isSuspended {
            return .needsScheduling
        }
        return .alreadyScheduled
    }

    /// DANGER: Must ONLY be invoked synchronously from an aborted or closed run state.
    /// No concurrent enqueue is allowed: the mailbox must already be terminating.
    internal func sendSystemTombstone() {
        traceLog_Mailbox(self.id.path, "SEND SYSTEM TOMBSTONE", file: #fileID, line: #line)

        guard let shell = self.shell else {
            traceLog_Mailbox(
                self.id.path,
                "has already released the actor cell, dropping system tombstone",
                file: #fileID,
                line: #line
            )
            return
        }

        let oldStatus: Status = self.setHasSystemMessages()

        guard oldStatus.isTerminating else {
            fatalError(
                """
                !!! BUG !!! Tombstone was attempted to be enqueued at not terminating actor.
                Address: \(self.id)
                System: \(self.shell?.actorSystem?.description ?? "<no system>")
                """
            )
        }

        self.systemMessages.enqueue(.tombstone)

        // Only the run that initiates termination enqueues a tombstone, exactly once.
        shell.messageDispatcher.execute(self.run)
    }

    deinit {
        #if SACT_TESTS_LEAKS
        if self.id.segments.first?.value == "user" {
            _ = self.deadLetters.actorSystem?.userMailboxInitCounter.loadThenWrappingDecrement(ordering: .relaxed)
        }
        #endif
    }
}
