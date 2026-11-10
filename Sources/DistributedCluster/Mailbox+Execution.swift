import Atomics
import CoreMetrics
import DistributedActorsConcurrencyHelpers
import Logging

extension Mailbox {
    private enum MailboxRunResult {
        case close
        case closed
        case done
        case reschedule
    }

    internal func run() {
        guard let shell = self.shell else {
            traceLog_Mailbox(
                self.id.path,
                "has already stopped, ignoring run",
                file: #fileID,
                line: #line
            )
            return
        }
        let mailboxRunResult: MailboxRunResult = self.mailboxRun(shell)
        switch mailboxRunResult {
        case .reschedule:
            shell.messageDispatcher.execute(self.run)

        case .done:
            return

        case .close:
            // Set terminating before enqueuing the tombstone so concurrent sends become dead letters.
            traceLog_Mailbox(self.id.path, "interpret CLOSE", file: #fileID, line: #line)
            self.sendSystemTombstone()

        case .closed:
            traceLog_Mailbox(
                self.id.path,
                "finishTerminating has completed, and the final run has completed. We are CLOSED.",
                file: #fileID,
                line: #line
            )
        }
    }

    private func mailboxRun(_ shell: ActorShell<Message>) -> MailboxRunResult {
        let initialStatus: Status = self.setProcessingSystemMessages()
        shell.metrics[gauge: .mailboxCount]?.record(initialStatus.messageCount)
        guard !initialStatus.isClosed else {
            shell.log.warning("!!! BUG !!! Run was scheduled on already closed mailbox.")
            return .closed
        }
        var processedActivations: UInt64 =
            initialStatus.hasSystemMessages ? MailboxBitMasks.processingSystemMessages : 0
        let runLength: UInt64 =
            (min(initialStatus.messageCount, UInt64(self.maxRunLength)) << 2) + processedActivations
        var runResult: ActorRunResult = initialStatus.isSuspended ? .shouldSuspend : .continueRunning
        if initialStatus.hasSystemMessages {
            self.processSystemMessages(shell, initialStatus: initialStatus, runResult: &runResult)
        }
        self.updateSuspension(shell, initialStatus: initialStatus, runResult: runResult)
        self.processUserMessages(
            shell,
            initialStatus: initialStatus,
            runLength: runLength,
            processedActivations: &processedActivations,
            runResult: &runResult
        )
        return self.finishRun(
            shell,
            initialStatus: initialStatus,
            processedActivations: processedActivations,
            runResult: runResult
        )
    }

    private func processSystemMessages(
        _ shell: ActorShell<Message>,
        initialStatus: Status,
        runResult: inout ActorRunResult
    ) {
        while runResult != .shouldStop,
            runResult != .closed,
            let message = self.systemMessages.dequeue() {
            do {
                runResult = try shell.interpretSystemMessage(message: message)
            } catch {
                shell.fail(error)
                runResult = .shouldStop
            }
        }
        if runResult == .shouldStop || runResult == .closed {
            if !initialStatus.isTerminating {
                self.setTerminating()
            }
            // System messages, including posthumous watch requests, must drain before user messages.
            while let message = self.systemMessages.dequeue() {
                traceLog_Mailbox(
                    shell.path,
                    "CLOSED, yet pending system messages still made it in... draining...",
                    file: #fileID,
                    line: #line
                )
                self.deadLetters.tell(DeadLetter(message, recipient: self.id))
            }
        }
    }

    private func updateSuspension(_ shell: ActorShell<Message>, initialStatus: Status, runResult: ActorRunResult) {
        if initialStatus.isSuspended, runResult != .shouldSuspend {
            self.resetStatusSuspended()
        } else if !initialStatus.isSuspended, runResult == .shouldSuspend {
            self.setStatusSuspended()
            traceLog_Mailbox(shell.path, "MARKED SUSPENDED", file: #fileID, line: #line)
        }
    }

    private func processUserMessages(
        _ shell: ActorShell<Message>,
        initialStatus: Status,
        runLength: UInt64,
        processedActivations: inout UInt64,
        runResult: inout ActorRunResult
    ) {
        if runResult == .continueRunning {
            while processedActivations < runLength,
                runResult == .continueRunning,
                let envelope = self.userMessages.dequeue() {
                processedActivations += MailboxBitMasks.singleUserMessage
                do {
                    runResult = try self.interpret(envelope, using: shell)
                } catch {
                    shell.fail(error)
                    runResult = .shouldStop
                }
                if runResult == .shouldStop, !initialStatus.isTerminating {
                    self.setTerminating()
                    traceLog_Mailbox(shell.path, "MARKED TERMINATING", file: #fileID, line: #line)
                    break
                }
                if runResult == .shouldSuspend {
                    self.setStatusSuspended()
                    traceLog_Mailbox(shell.path, "MARKED SUSPENDED", file: #fileID, line: #line)
                    break
                }
                if processedActivations >= runLength {
                    break
                }
            }
        } else if runResult == .shouldSuspend {
            traceLog_Mailbox(
                shell.path,
                "MAILBOX SUSPENDED, SKIPPING USER MESSAGE PROCESSING",
                file: #fileID,
                line: #line
            )
        } else {
            while let message = self.userMessages.dequeue() {
                self.deadLetters.tell(DeadLetter(message, recipient: self.id))
                processedActivations += MailboxBitMasks.singleUserMessage
            }
        }
    }

    private func interpret(_ envelope: Payload, using shell: ActorShell<Message>) throws -> ActorRunResult {
        switch envelope.payload {
        case .message(let untypedMessage):
            traceLog_Mailbox(self.id.path, "INVOKE MSG: \(envelope)", file: #fileID, line: #line)
            guard let typedMessage = untypedMessage as? Message else {
                fatalError("Received message [\(untypedMessage)]:\(type(of: untypedMessage)), expected \(Message.self)")
            }
            return try shell.interpretMessage(message: typedMessage)

        case .closure(let carry):
            traceLog_Mailbox(
                self.id.path,
                "INVOKE CLOSURE: \(String(describing: carry.function)) defined at \(carry.file):\(carry.line)",
                file: #fileID,
                line: #line
            )
            return try shell.interpretClosure(carry)

        case .adaptedMessage(let carry):
            traceLog_Mailbox(
                self.id.path,
                "INVOKE ADAPTED MESSAGE: \(carry.message)",
                file: #fileID,
                line: #line
            )
            return try shell.interpretAdaptedMessage(carry)

        case .subMessage(let carry):
            traceLog_Mailbox(
                self.id.path,
                "INVOKE SUBMSG: \(carry.message) with identifier \(carry.identifier)",
                file: #fileID,
                line: #line
            )
            return try shell.interpretSubMessage(carry)
        }
    }

    private func finishRun(
        _ shell: ActorShell<Message>,
        initialStatus: Status,
        processedActivations: UInt64,
        runResult: ActorRunResult
    ) -> MailboxRunResult {
        let oldStatus: Status = self.decrementActivations(by: processedActivations)
        let oldActivations: UInt64 = oldStatus.activations
        traceLog_Mailbox(shell.path, "Run complete...", file: #fileID, line: #line)
        // Stop takes precedence over rescheduling: system start may immediately stop the actor.
        if runResult == .shouldStop {
            traceLog_Mailbox(shell.path, "Terminating...", file: #fileID, line: #line)
            let processedActivationsCount: UInt64 = Status(processedActivations).messageCount
            if initialStatus.messageCount >= processedActivationsCount {
                shell.metrics[gauge: .mailboxCount]?.record(initialStatus.messageCount - processedActivationsCount)
            } else {
                shell.log.warning(
                    """
                    Mailbox closed with more processed activations (\(processedActivationsCount)) \
                    than messages (\(initialStatus.messageCount))
                    """,
                    metadata: ["status": "\(initialStatus)", "processedActivations": "\(processedActivations)"]
                )
            }
            return .close
        }
        if runResult == .closed {
            traceLog_Mailbox(shell.path, "Terminating, completely closed now...", file: #fileID, line: #line)
            shell.metrics[gauge: .mailboxCount]?.record(0)
            return .closed
        }
        if (oldActivations > processedActivations && !oldStatus.isSuspended) || oldStatus.hasSystemMessages {
            traceLog_Mailbox(
                shell.path,
                "Rescheduling... \(oldActivations) :: \(processedActivations)",
                file: #fileID,
                line: #line
            )
            // Concurrent enqueue already updated metrics; the next run refreshes the count.
            return .reschedule
        }
        traceLog_Mailbox(shell.path, "Run complete, shouldReschedule:false", file: #fileID, line: #line)
        shell.metrics[gauge: .mailboxCount]?.record(0)
        return .done
    }
}
