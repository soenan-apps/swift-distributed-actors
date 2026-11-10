import Atomics

extension Mailbox {
    internal struct Status {
        // Implementation notes:
        // State should be operated on bitwise; where the specific bits signify states like the following:
        //      0 - has system messages
        //      1 - currently processing system messages
        //   2-33 - user message count
        //     34 - message count overflow (incremented before checking capacity)
        //  35-60 - reserved
        //     61 - mailbox is suspended and will not process any user messages
        //     62 - terminating (or closed)
        //     63 - closed, terminated (for sure)
        // Activation count is special in the sense that we use it as follows, it's value being:
        // 0 - inactive, not scheduled and no messages to process
        // 1 - active without(!) normal messages, only system messages are to be processed
        // n - there are (n >> 1) messages to process + system messages if LSB is set
        //
        // Note that this implementation allows, using one load, to know:
        // - if the actor is running right now (so the mailbox size will be decremented shortly),
        // - current mailbox size (nr. of enqueued messages, which can be used for scheduling and/or metrics)
        // - if we need to schedule it or not since it was scheduled already etc.
        private let rawStatus: UInt64

        internal var messageCount: UInt64 {
            self.activations >> 2
        }

        internal var hasSystemMessages: Bool {
            (self.rawStatus & MailboxBitMasks.hasSystemMessages) != 0
        }

        internal var isProcessingSystemMessages: Bool {
            (self.rawStatus & MailboxBitMasks.processingSystemMessages) != 0
        }

        internal var activations: UInt64 {
            (self.rawStatus & MailboxBitMasks.activations)
        }

        internal var isSuspended: Bool {
            (self.rawStatus & MailboxBitMasks.suspended) != 0
        }

        internal var isTerminating: Bool {
            (self.rawStatus & MailboxBitMasks.terminating) != 0
        }

        internal var isClosed: Bool {
            (self.rawStatus & MailboxBitMasks.closed) != 0
        }

        internal init(_ status: UInt64) {
            self.rawStatus = status
        }
    }

    internal var status: Status {
        Status(self.atomicStatus.load(ordering: .sequentiallyConsistent))
    }

    internal func incrementMessageCount() -> Status {
        Status(
            self.atomicStatus.loadThenWrappingIncrement(
                by: MailboxBitMasks.singleUserMessage,
                ordering: .sequentiallyConsistent
            )
        )
    }

    internal func decrementMessageCount() -> Status {
        Status(
            self.atomicStatus.loadThenWrappingDecrement(
                by: MailboxBitMasks.singleUserMessage,
                ordering: .sequentiallyConsistent
            )
        )
    }

    internal func decrementActivations(by count: UInt64) -> Status {
        Status(
            self.atomicStatus.loadThenWrappingDecrement(
                by: count,
                ordering: .sequentiallyConsistent
            )
        )
    }

    internal func setHasSystemMessages() -> Status {
        Status(
            self.atomicStatus.loadThenBitwiseOr(
                with: MailboxBitMasks.hasSystemMessages,
                ordering: .sequentiallyConsistent
            )
        )
    }

    // Checks if the 'has system messages' bit is set and if it is, unsets it and
    // sets the 'is processing system messages' bit in one atomic operation. This is
    // necessary to not race between unsetting the bit at the end of a run while
    // another thread is enqueueing a new system message.
    internal func setProcessingSystemMessages() -> Status {
        let currentStatus: Status = self.status
        if currentStatus.hasSystemMessages {
            return Status(
                self.atomicStatus.loadThenBitwiseXor(
                    with: MailboxBitMasks.becomeSysMsgProcessingXor,
                    ordering: .sequentiallyConsistent
                )
            )
        }

        return currentStatus
    }

    @discardableResult
    internal func setTerminating() -> Status {
        Status(
            self.atomicStatus.loadThenBitwiseOr(
                with: MailboxBitMasks.terminating,
                ordering: .sequentiallyConsistent
            )
        )
    }

    @discardableResult
    internal func setFailed() -> Status {
        self.setTerminating()
    }

    @discardableResult
    internal func setClosed() -> Status {
        Status(
            self.atomicStatus.loadThenBitwiseOr(
                with: MailboxBitMasks.closed,
                ordering: .sequentiallyConsistent
            )
        )
    }

    @discardableResult
    internal func setStatusSuspended() -> Status {
        Status(
            self.atomicStatus.loadThenBitwiseOr(
                with: MailboxBitMasks.suspended,
                ordering: .sequentiallyConsistent
            )
        )
    }

    @discardableResult
    internal func resetStatusSuspended() -> Status {
        Status(
            self.atomicStatus.loadThenBitwiseAnd(
                with: MailboxBitMasks.unsuspend,
                ordering: .sequentiallyConsistent
            )
        )
    }
}
