// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsConcurrencyHelpers

internal class CountDownLatch: CustomStringConvertible {
    private var counter: Int
    private let condition: ClusterCondition
    private let lock: ClusterMutex

    internal var count: Int {
        self.lock.synchronized {
            self.counter
        }
    }

    internal var description: String {
        "CountDownLatch(remaining:\(self.count)"
    }

    internal init(from: Int) {
        self.counter = from
        self.condition = ClusterCondition()
        self.lock = ClusterMutex()
    }

    /// Returns previous value before the decrement was issued.
    internal func countDown() {
        self.lock.synchronized {
            self.counter -= 1

            if self.counter == 0 {
                self.condition.signalAll()
            }
        }
    }

    internal func wait(atMost duration: Duration? = nil) {
        self.lock.synchronized {
            while true {
                if self.counter == 0 {
                    return  // done
                }

                if let duration = duration {
                    _ = self.condition.wait(lock, atMost: duration)
                } else {
                    self.condition.wait(lock)
                }
            }
        }
    }
}
