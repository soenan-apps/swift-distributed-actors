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

// ===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

// Based on SwiftNIO's Heap at revision bf2598d19359e43b4cfaffaff250986ebe677721.

// Modified by Soenan for musl platform support.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// Slightly modified version of NIO's Heap. upstream changes
internal struct Heap<T: Equatable>: CustomDebugStringConvertible, Sequence {
    internal typealias Element = T

    internal private(set) var storage: ContiguousArray<T> = []
    private let comparator: (T, T) -> Bool
    internal var debugDescription: String {
        guard !self.storage.isEmpty else {
            return "<empty heap>"
        }

        let descriptions: [String] = self.storage.map { String(describing: $0) }
        let maxLen: Int = descriptions.reduce(0) { Swift.max($0, $1.count) }
        let paddedDescs: [String] = descriptions.map { (description: String) -> String in
            var desc: String = description
            while desc.count < maxLen {
                if desc.count.isMultiple(of: 2) {
                    desc = " \(desc)"
                } else {
                    desc = "\(desc) "
                }
            }
            return desc
        }

        var all: String = "\n"
        let spacing: String = String(repeating: " ", count: maxLen)
        func subtreeWidths(rootIndex: Int) -> (Int, Int) {
            let lcIdx: Int = self.leftIndex(rootIndex)
            let rcIdx: Int = self.rightIndex(rootIndex)
            var leftSpace: Int = 0
            var rightSpace: Int = 0
            if lcIdx < self.storage.count {
                let sws: (Int, Int) = subtreeWidths(rootIndex: lcIdx)
                leftSpace += sws.0 + sws.1 + maxLen
            }
            if rcIdx < self.storage.count {
                let sws: (Int, Int) = subtreeWidths(rootIndex: rcIdx)
                rightSpace += sws.0 + sws.1 + maxLen
            }
            return (leftSpace, rightSpace)
        }
        for (index, desc) in paddedDescs.enumerated() {
            let (leftWidth, rightWidth): (Int, Int) = subtreeWidths(rootIndex: index)
            all += String(repeating: " ", count: leftWidth)
            all += desc
            all += String(repeating: " ", count: rightWidth)

            func height(index: Int) -> Int {
                Int(log2(Double(index + 1)))
            }

            let myHeight: Int = height(index: index)
            let nextHeight: Int = height(index: index + 1)
            if myHeight != nextHeight {
                all += "\n"
            } else {
                all += spacing
            }
        }
        all += "\n"
        return all
    }

    internal var startIndex: Int { self.storage.startIndex }
    internal var endIndex: Int { self.storage.endIndex }

    internal var underestimatedCount: Int {
        self.storage.count
    }

    internal var count: Int {
        self.storage.count
    }

    internal init(of _: T.Type, comparator: @escaping (T, T) -> Bool) {
        self.comparator = comparator
    }

    // named `PARENT` in CLRS
    private func parentIndex(_ index: Int) -> Int {
        (index - 1) / 2
    }

    // named `LEFT` in CLRS
    private func leftIndex(_ index: Int) -> Int {
        2 * index + 1
    }

    // named `RIGHT` in CLRS
    private func rightIndex(_ index: Int) -> Int {
        2 * index + 2
    }

    // named `MAX-HEAPIFY` in CLRS
    private mutating func heapify(_ index: Int) {
        let left: Int = self.leftIndex(index)
        let right: Int = self.rightIndex(index)

        var root: Int
        if left <= (self.storage.count - 1), self.comparator(self.storage[left], self.storage[index]) {
            root = left
        } else {
            root = index
        }

        if right <= (self.storage.count - 1), self.comparator(self.storage[right], self.storage[root]) {
            root = right
        }

        if root != index {
            self.storage.swapAt(index, root)
            self.heapify(root)
        }
    }

    // named `HEAP-INCREASE-KEY` in CRLS
    private mutating func heapRootify(index startingIndex: Int, key: T) {
        var index: Int = startingIndex
        if self.comparator(self.storage[index], key) {
            fatalError("New key must be closer to the root than current key")
        }

        self.storage[index] = key
        while index > 0, self.comparator(self.storage[index], self.storage[self.parentIndex(index)]) {
            self.storage.swapAt(index, self.parentIndex(index))
            index = self.parentIndex(index)
        }
    }

    internal mutating func append(_ value: T) {
        var index: Int = self.storage.count
        self.storage.append(value)
        while index > 0, self.comparator(self.storage[index], self.storage[self.parentIndex(index)]) {
            self.storage.swapAt(index, self.parentIndex(index))
            index = self.parentIndex(index)
        }
    }

    @discardableResult
    internal mutating func removeRoot() -> T? {
        self.remove(index: 0)
    }

    @discardableResult
    internal mutating func remove(value: T) -> Bool {
        if let idx = self.storage.firstIndex(of: value) {
            self.remove(index: idx)
            return true
        }
        return false
    }

    @discardableResult
    internal mutating func remove(where: (T) throws -> Bool) rethrows -> Bool {
        if let idx = try self.storage.firstIndex(where: `where`) {
            self.remove(index: idx)
            return true
        }
        return false
    }

    @discardableResult
    private mutating func remove(index: Int) -> T? {
        guard !self.storage.isEmpty else {
            return nil
        }

        let element: T = self.storage[index]
        if self.storage.count == 1 || self.storage[index] == self.storage[self.storage.count - 1] {
            self.storage.removeLast()
        } else if !self.comparator(self.storage[index], self.storage[self.storage.count - 1]) {
            self.heapRootify(index: index, key: self.storage[self.storage.count - 1])
            self.storage.removeLast()
        } else {
            self.storage[index] = self.storage[self.storage.count - 1]
            self.storage.removeLast()
            self.heapify(index)
        }
        return element
    }

    internal func checkHeapProperty() -> Bool {
        func checkHeapProperty(index: Int) -> Bool {
            let leftIndex: Int = self.leftIndex(index)
            let rightIndex: Int = self.rightIndex(index)
            if index >= self.storage.count {
                return true
            }

            let element: T = self.storage[index]
            var leftCondition: Bool = true
            var rightCondition: Bool = true
            if leftIndex < self.storage.count {
                let left: T = self.storage[leftIndex]
                leftCondition = !self.comparator(left, element)
            }
            if rightIndex < self.storage.count {
                let right: T = self.storage[rightIndex]
                rightCondition = !self.comparator(right, element)
            }
            return leftCondition && rightCondition
                && checkHeapProperty(index: leftIndex) && checkHeapProperty(index: rightIndex)
        }
        return checkHeapProperty(index: 0)
    }

    internal func makeIterator() -> HeapIterator<T> {
        HeapIterator(heap: self)
    }

    internal func index(after index: Int) -> Int {
        index + 1
    }

    internal subscript(position: Int) -> T {
        self.storage[position]
    }

}

extension Heap where T: Comparable {
    internal init?(type: HeapType, storage: ContiguousArray<T>) {
        self.comparator = type.comparator(type: T.self)
        self.storage = storage
        if !self.checkHeapProperty() {
            return nil
        }
    }

    internal init(type: HeapType) {
        self.comparator = type.comparator(type: T.self)
    }
}
