// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

@usableFromInline
internal class RingBufferIterator<Element>: IteratorProtocol {
    @usableFromInline internal let buffer: RingBuffer<Element>
    @usableFromInline internal var count: Int

    @usableFromInline internal var isEmpty: Bool {
        // Using isEmpty to implement this getter would recurse.
        // swiftlint:disable:next empty_count
        self.count == 0
    }

    @usableFromInline
    internal init(buffer: RingBuffer<Element>, count: Int) {
        assert(count >= 0, "count can't be less than 0")
        self.buffer = buffer
        self.count = count
    }

    @inlinable
    internal func next() -> Element? {
        if self.isEmpty {
            return nil
        }
        self.count -= 1
        return self.buffer.take()
    }

    @inlinable
    internal func take(_ count: Int) -> RingBufferIterator {
        RingBufferIterator(buffer: self.buffer, count: min(self.count, count))
    }
}
