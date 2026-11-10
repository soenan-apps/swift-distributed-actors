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
import DistributedActorsConcurrencyHelpers

@usableFromInline
internal final class MPSCLinkedQueue<Element> {
    @usableFromInline internal let queue: UnsafeMutablePointer<CSActMPSCLinkedQueue>

    internal init() {
        self.queue = c_sact_mpsc_linked_queue_create()
    }

    /// Adds the given item to the end of the queue. This operation is atomic,
    /// wait free, and will always succeed.
    ///
    /// - Parameter item: The item to be added to the queue
    @inlinable
    internal func enqueue(_ item: Element) {
        let pointer: UnsafeMutablePointer<Element> = .allocate(capacity: 1)
        pointer.initialize(to: item)
        c_sact_mpsc_linked_queue_enqueue(self.queue, pointer)
    }

    /// Removes the current head from the queue and returns it. This operation
    /// is only safe to be called from a single thread, but can be called
    /// concurrently with any number of calls to `enqueue`. This operation
    /// is lock-free, but not wait-free. If a new item has been added to the
    /// queue, but is not connected yet, this call will spin until the item
    /// is visible.
    ///
    /// - Returns: The head of the queue if it is non-empty, `nil` otherwise.
    @inlinable
    internal func dequeue() -> Element? {
        if let rawPointer = c_sact_mpsc_linked_queue_dequeue(self.queue) {
            let pointer: UnsafeMutablePointer<Element> = rawPointer.assumingMemoryBound(to: Element.self)
            defer {
                pointer.deallocate()
            }
            return pointer.move()
        }

        return nil
    }

    deinit {
        while dequeue() != nil {
            continue
        }
        c_sact_mpsc_linked_queue_destroy(self.queue)
    }
}
