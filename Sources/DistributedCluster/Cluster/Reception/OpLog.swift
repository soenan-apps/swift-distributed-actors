// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

internal protocol OpLogStreamOp {}
internal class OpLog<Op: OpLogStreamOp> {
    internal typealias SequenceNr = UInt64

    internal enum ReplayFrom {
        case beginning
        case sequenceNr(SequenceNr)
    }

    /// Tracks the confirmed sequence number and replays the next unconfirmed batch.
    internal struct Replayer {
        private let opStream: OpLog<Op>
        private var atIndex: Array<Op>.Index
        internal var atSeqNr: SequenceNr

        internal init(opStream: OpLog<Op>, atIndex: Array<Op>.Index, atSeqNr: SequenceNr) {
            self.opStream = opStream
            self.atIndex = atIndex
            self.atSeqNr = atSeqNr
        }

        internal mutating func confirm(until newSeqNr: SequenceNr) {
            guard newSeqNr > self.atSeqNr else {
                return
            }
            self.atSeqNr = newSeqNr
            for operation in self.opStream.ops[self.atIndex...] {
                self.atIndex += 1
                if operation.sequenceRange.includes(newSeqNr) {
                    return
                }
            }
        }

        internal func nextOpsChunk() -> ArraySlice<SequencedOp> {
            guard self.atIndex < self.opStream.ops.endIndex else {
                return .init()
            }
            return self.opStream.ops[self.atIndex...].prefix(self.opStream.batchSize)
        }
    }

    /// An operation and the inclusive sequence range represented by that operation.
    internal struct SequencedOp {
        internal let sequenceRange: OpLogSequenceRange
        internal let operation: Op

        internal init(sequenceRange: OpLogSequenceRange, op operation: Op) {
            self.sequenceRange = sequenceRange
            self.operation = operation
        }
    }

    internal var ops: [SequencedOp]
    internal var minSeqNr: SequenceNr
    internal var maxSeqNr: SequenceNr
    internal let batchSize: Int

    internal var count: Int {
        self.ops.count
    }

    internal init(of _: Op.Type, batchSize: Int) {
        self.ops = []
        self.batchSize = batchSize
        self.minSeqNr = 0
        self.maxSeqNr = 0
    }

    @discardableResult
    internal func add(_ operation: Op) -> SequencedOp {
        self.maxSeqNr += 1
        let sequencedOp: SequencedOp = SequencedOp(
            sequenceRange: .single(self.maxSeqNr),
            op: operation
        )
        self.ops.append(sequencedOp)
        return sequencedOp
    }

    internal func compact(_ compaction: ([SequencedOp]) -> [SequencedOp]) {
        self.ops = compaction(self.ops)
    }

    internal func replay(from _: ReplayFrom) -> Replayer {
        .init(opStream: self, atIndex: self.ops.startIndex, atSeqNr: self.minSeqNr)
    }

}
extension OpLog.SequencedOp: Equatable where Op: Equatable {}
