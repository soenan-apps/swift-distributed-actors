// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2024 Apple Inc. and the Swift Distributed Actors project authors
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

import XCTest

@testable import DistributedCluster

internal func getRandomNumbers(count: Int) -> [UInt8] {
    var values: [UInt8] = .init(repeating: 0, count: count)
    let fileDescriptor: Int32 = open("/dev/urandom", O_RDONLY)
    precondition(fileDescriptor >= 0)
    defer {
        close(fileDescriptor)
    }
    _ = values.withUnsafeMutableBytes { ptr in
        read(fileDescriptor, ptr.baseAddress, ptr.count)
    }
    return values
}

internal final class HeapTests: XCTestCase {
    internal func testSimple() {
        var handler: Heap<Int> = Heap<Int>(type: .maxHeap)
        handler.append(1)
        handler.append(3)
        handler.append(2)
        XCTAssertEqual(3, handler.removeRoot())
        XCTAssertTrue(handler.checkHeapProperty())
    }

    internal func testSortedDesc() {
        var maxHeap: Heap<Int> = Heap<Int>(type: .maxHeap)
        var minHeap: Heap<Int> = Heap<Int>(type: .minHeap)

        let input: [Int] = [16, 14, 10, 9, 8, 7, 4, 3, 2, 1]
        for value in input {
            minHeap.append(value)
            maxHeap.append(value)
            XCTAssertTrue(minHeap.checkHeapProperty())
            XCTAssertTrue(maxHeap.checkHeapProperty())
        }
        var minHeapInputPtr: Int = input.count - 1
        var maxHeapInputPtr: Int = 0
        while let maxE = maxHeap.removeRoot(), let minE = minHeap.removeRoot() {
            XCTAssertEqual(maxE, input[maxHeapInputPtr], "\(maxHeap.debugDescription)")
            XCTAssertEqual(minE, input[minHeapInputPtr])
            maxHeapInputPtr += 1
            minHeapInputPtr -= 1
            XCTAssertTrue(minHeap.checkHeapProperty(), "\(minHeap.debugDescription)")
            XCTAssertTrue(maxHeap.checkHeapProperty())
        }
        XCTAssertEqual(-1, minHeapInputPtr)
        XCTAssertEqual(input.count, maxHeapInputPtr)
    }

    internal func testSortedAsc() {
        var maxHeap: Heap<Int> = Heap<Int>(type: .maxHeap)
        var minHeap: Heap<Int> = Heap<Int>(type: .minHeap)

        let input: [Int] = Array([16, 14, 10, 9, 8, 7, 4, 3, 2, 1].reversed())
        for value in input {
            minHeap.append(value)
            maxHeap.append(value)
        }
        var minHeapInputPtr: Int = 0
        var maxHeapInputPtr: Int = input.count - 1
        while let maxE = maxHeap.removeRoot(), let minE = minHeap.removeRoot() {
            XCTAssertEqual(maxE, input[maxHeapInputPtr])
            XCTAssertEqual(minE, input[minHeapInputPtr])
            maxHeapInputPtr -= 1
            minHeapInputPtr += 1
        }
        XCTAssertEqual(input.count, minHeapInputPtr)
        XCTAssertEqual(-1, maxHeapInputPtr)
    }

    internal func testSortedCustom() {
        struct Test: Equatable {
            let valueForTest: Int
        }

        var maxHeap: Heap<Test> = Heap(of: Test.self) { closureArgument, closureArgument2 in
            closureArgument.valueForTest > closureArgument2.valueForTest
        }
        var minHeap: Heap<Test> = Heap(of: Test.self) { closureArgument, closureArgument2 in
            closureArgument.valueForTest < closureArgument2.valueForTest
        }

        let input: [Test] = Array([16, 14, 10, 9, 8, 7, 4, 3, 2, 1].reversed().map { Test(valueForTest: $0) })
        for value in input {
            minHeap.append(value)
            maxHeap.append(value)
        }
        var minHeapInputPtr: Int = 0
        var maxHeapInputPtr: Int = input.count - 1
        while let maxE = maxHeap.removeRoot(), let minE = minHeap.removeRoot() {
            XCTAssertEqual(maxE, input[maxHeapInputPtr])
            XCTAssertEqual(minE, input[minHeapInputPtr])
            maxHeapInputPtr -= 1
            minHeapInputPtr += 1
        }
        XCTAssertEqual(input.count, minHeapInputPtr)
        XCTAssertEqual(-1, maxHeapInputPtr)
    }

    internal func testAddAndRemoveRandomNumbers() throws {
        var maxHeap: Heap<UInt8> = Heap<UInt8>(type: .maxHeap)
        var minHeap: Heap<UInt8> = Heap<UInt8>(type: .minHeap)
        var maxHeapLast: UInt8 = UInt8.max
        var minHeapLast: UInt8 = UInt8.min

        let elementCount: Int = 100

        for number in getRandomNumbers(count: elementCount) {
            maxHeap.append(number)
            minHeap.append(number)
            XCTAssertTrue(maxHeap.checkHeapProperty(), maxHeap.debugDescription)
            XCTAssertTrue(minHeap.checkHeapProperty(), maxHeap.debugDescription)

            XCTAssertEqual(Array(minHeap.sorted()), Array(minHeap))
            XCTAssertEqual(Array(maxHeap.sorted().reversed()), Array(maxHeap))
        }

        for _ in 0..<elementCount / 2 {
            var value: UInt8 = try XCTUnwrap(maxHeap.removeRoot())
            XCTAssertLessThanOrEqual(value, maxHeapLast)
            maxHeapLast = value
            value = try XCTUnwrap(minHeap.removeRoot())
            XCTAssertGreaterThanOrEqual(value, minHeapLast)
            minHeapLast = value

            XCTAssertTrue(minHeap.checkHeapProperty())
            XCTAssertTrue(maxHeap.checkHeapProperty())

            XCTAssertEqual(Array(minHeap.sorted()), Array(minHeap))
            XCTAssertEqual(Array(maxHeap.sorted().reversed()), Array(maxHeap))
        }

        maxHeapLast = UInt8.max
        minHeapLast = UInt8.min

        for number in getRandomNumbers(count: elementCount) {
            maxHeap.append(number)
            minHeap.append(number)
            XCTAssertTrue(maxHeap.checkHeapProperty(), maxHeap.debugDescription)
            XCTAssertTrue(minHeap.checkHeapProperty(), maxHeap.debugDescription)
        }

        for _ in 0..<elementCount / 2 + elementCount {
            var value: UInt8 = try XCTUnwrap(maxHeap.removeRoot())
            XCTAssertLessThanOrEqual(value, maxHeapLast)
            maxHeapLast = value
            value = try XCTUnwrap(minHeap.removeRoot())
            XCTAssertGreaterThanOrEqual(value, minHeapLast)
            minHeapLast = value

            XCTAssertTrue(minHeap.checkHeapProperty())
            XCTAssertTrue(maxHeap.checkHeapProperty())
        }

        XCTAssertEqual(0, minHeap.underestimatedCount)
        XCTAssertEqual(0, maxHeap.underestimatedCount)
    }

    internal func testRemoveElement() throws {
        var handler: Heap<Int> = try XCTUnwrap(Heap<Int>(type: .maxHeap, storage: [84, 22, 19, 21, 3, 10, 6, 5, 20]))
        _ = handler.remove(value: 10)
        XCTAssertTrue(handler.checkHeapProperty(), "\(handler.debugDescription)")
    }
}
