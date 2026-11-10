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

import XCTest

@testable import DistributedCluster

internal final class MPSCLinkedQueueTests: XCTestCase {
    internal func test_dequeueWhenEmpty() {
        let queue: MPSCLinkedQueue<Int> = MPSCLinkedQueue<Int>()

        XCTAssertNil(queue.dequeue())
    }

    internal func test_enqueueDequeue() {
        let queue: MPSCLinkedQueue<Int> = MPSCLinkedQueue<Int>()
        queue.enqueue(1)

        XCTAssertEqual(1, queue.dequeue())
    }

    internal func test_concurrentEnqueueDequeue() throws {
        let writerCount: Int = 6
        let messageCountPerWriter: Int = 10_000
        let totalMessageCount: Int = writerCount * messageCountPerWriter
        let queue: MPSCLinkedQueue<Int> = MPSCLinkedQueue<Int>()

        for _ in 1...writerCount {
            _ = try ClusterThread {
                for index in 0..<messageCountPerWriter {
                    queue.enqueue(index)
                }
            }
        }

        var dequeued: Int = 0
        while dequeued < totalMessageCount {
            if queue.dequeue() != nil {
                dequeued += 1
            }
        }
    }
}
