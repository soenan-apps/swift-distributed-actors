import Atomics

internal enum MailboxBitMasks {
    internal static let activations: UInt64 =
        0b0000_0000_0000_0000_0000_0000_0000_0111_1111_1111_1111_1111_1111_1111_1111_1111

    internal static let hasSystemMessages: UInt64 =
        0b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0001
    internal static let processingSystemMessages: UInt64 =
        0b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0010

    // Implementation notes about Termination:
    // Termination MUST first set TERMINATING and only after add the "final" CLOSED state.
    // In other words, the only legal bit states a mailbox should observe are:
    //  -> 0b000... alive,
    //  -> 0b001... suspended (waiting for AsyncResult; only system messages are processed),
    //  -> 0b010... terminating,
    //  -> 0b110... closed (also known as: "terminated", "dead")
    //
    // Meaning that `0b100...` is NOT legal.
    internal static let suspended: UInt64 =
        0b0010_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000
    internal static let terminating: UInt64 =
        0b0100_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000
    internal static let closed: UInt64 =
        0b1000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000

    // user message count is stored in bits 2-61, so when incrementing or
    // decrementing the message count, we need to add starting at bit 2
    internal static let singleUserMessage: UInt64 =
        0b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0100

    // Mask to use with XOR on the status to unset the 'has system messages' bit
    // and set the 'is processing system messages' bit in a single atomic operation
    internal static let becomeSysMsgProcessingXor: UInt64 =
        0b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0011

    // used to unset the SUSPENDED bit by ANDing with status
    //
    // assume we are suspended and have some system messages and 7 user messages enqueued:
    //      CURRENT STATUS         0b0010_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0001_1101
    //      (operation)          &
    internal static let unsuspend: UInt64 =
        0b1101_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111
    //                             --------------------------------------------------------------------
    //                           = 0b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0001_1101
}
