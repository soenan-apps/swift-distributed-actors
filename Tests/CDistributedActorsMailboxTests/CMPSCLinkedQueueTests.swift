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

import CDistributedActorsMailbox
import Foundation
import XCTest

internal final class CMPSCLinkedQueueTests: XCTestCase {
    internal func testDequeueWhenEmpty() {
        let queue: UnsafeMutablePointer<CSActMPSCLinkedQueue>? = c_sact_mpsc_linked_queue_create()
        let res: UnsafeMutableRawPointer? = c_sact_mpsc_linked_queue_dequeue(queue)

        XCTAssertNil(res)
    }

    internal func testEnqueueDequeue() {
        let queue: UnsafeMutablePointer<CSActMPSCLinkedQueue>? = c_sact_mpsc_linked_queue_create()
        let pointer: UnsafeMutableRawPointer = UnsafeMutableRawPointer.allocate(byteCount: 0, alignment: 0)
        defer {
            pointer.deallocate()
        }

        c_sact_mpsc_linked_queue_enqueue(queue, pointer)
        let res: UnsafeMutableRawPointer? = c_sact_mpsc_linked_queue_dequeue(queue)

        XCTAssertEqual(pointer, res)
    }

    internal func testDestroy() {
        // jsut checking that it doesn't segfault here
        let queue: UnsafeMutablePointer<CSActMPSCLinkedQueue>? = c_sact_mpsc_linked_queue_create()
        let pointer: UnsafeMutableRawPointer = UnsafeMutableRawPointer.allocate(byteCount: 0, alignment: 0)

        c_sact_mpsc_linked_queue_enqueue(queue, pointer)
        c_sact_mpsc_linked_queue_destroy(queue)
    }
}
