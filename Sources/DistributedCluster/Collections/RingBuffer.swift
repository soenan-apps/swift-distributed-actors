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
internal final class RingBuffer<Element> {
    @usableFromInline internal var elements: [Element?]
    @usableFromInline internal var readCounter: Int
    @usableFromInline internal var writeCounter: Int
    @usableFromInline internal let capacity: Int

    @inlinable internal var writeIndex: Int? {
        if self.isFull {
            return nil
        }

        return self.writeCounter % self.capacity
    }

    @inlinable internal var readIndex: Int? {
        if self.isEmpty {
            return nil
        }

        return self.readCounter % self.capacity
    }

    @inlinable internal var count: Int {
        self.writeCounter - self.readCounter
    }

    @inlinable internal var isEmpty: Bool {
        self.readCounter == self.writeCounter
    }

    @inlinable internal var isFull: Bool {
        (self.writeCounter - self.readCounter) == self.capacity
    }

    @inlinable internal var iterator: RingBufferIterator<Element> {
        RingBufferIterator(buffer: self, count: self.count)
    }

    internal init(capacity: Int) {
        self.elements = [Element?](repeating: nil, count: capacity)
        self.readCounter = 0
        self.writeCounter = 0
        self.capacity = capacity
    }

    @inlinable
    internal func offer(element: Element) -> Bool {
        if let index = writeIndex {
            self.writeCounter += 1
            self.elements[index] = element
            return true
        }
        return false
    }

    @inlinable
    internal func take() -> Element? {
        if let index = readIndex {
            defer { elements[index] = nil }
            self.readCounter += 1
            return self.elements[index]
        }
        return nil
    }

    @inlinable
    internal func peek() -> Element? {
        if let index = readIndex {
            return self.elements[index]
        }
        return nil
    }
}
