// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

import struct Foundation.UUID

internal struct SingletonRemoteCallBuffer<Act: ClusterSingleton> {
    internal typealias Item = (callID: UUID, continuation: CheckedContinuation<Act, Error>)

    private var buffer: [Item] = []
    internal let capacity: Int

    internal var count: Int { self.buffer.count }
    internal var isFull: Bool { self.count >= self.capacity }
    internal var isEmpty: Bool { self.buffer.isEmpty }

    internal init(capacity: Int) {
        self.capacity = capacity
        self.buffer.reserveCapacity(capacity)
    }

    internal mutating func stash(_ item: Item) throws {
        guard self.count < self.capacity else {
            throw SingletonBufferError.full
        }
        self.buffer.append(item)
    }

    internal mutating func take() -> Item? {
        guard !self.isEmpty else {
            return nil
        }
        return self.buffer.removeFirst()
    }
}
