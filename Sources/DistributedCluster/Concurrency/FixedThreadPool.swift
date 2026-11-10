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

import Atomics
import DistributedActorsConcurrencyHelpers
import Foundation

// Discuss naming of `Worker`
private final class Worker {
    var thread: ClusterThread?
    var completedTasks: Int = 0

    private let mutex: ClusterMutex = .init()

    func lock() {
        self.mutex.lock()
    }

    func tryLock() -> Bool {
        self.mutex.tryLock()
    }

    func unlock() {
        self.mutex.unlock()
    }
}

/// 指定数のスレッドを開始し、shutdownまで並行して仕事を処理する。
public final class FixedThreadPool {
    @usableFromInline internal let taskQueue: LinkedBlockingQueue<() -> Void> = LinkedBlockingQueue()
    private var workers: [Worker] = []

    @usableFromInline internal let stopping: ManagedAtomic<Bool>

    @usableFromInline internal let runningWorkers: ManagedAtomic<Int>

    internal let allThreadsStopped: BlockingReceptacle<Void> = BlockingReceptacle()

    /// 指定した数のスレッドを開始する。
    public init(_ threadCount: Int) throws {
        self.stopping = .init(false)
        self.runningWorkers = .init(threadCount)

        for _ in 1...threadCount {
            let worker: Worker = Worker()
            let thread: ClusterThread = try ClusterThread {
                // threads in the pool keep running as long as the pool is not stopping
                while !self.stopping.load(ordering: .relaxed) {
                    // We are currently using a timed `poll` instead of indefinitely
                    //        blocking on `dequeue` because we need to be able to check
                    //        if the pool is stopping. `pthread_cancel` is problematic here
                    //        because if a thread is waiting on a `pthread_cond_t`, it will
                    //        re-acquire the mutex before cancelation, which is almost
                    //        guaranteed to cause a deadlock.
                    if let runnable = self.taskQueue.poll(.milliseconds(100)) {
                        worker.lock()
                        defer { worker.unlock() }
                        runnable()
                        worker.completedTasks += 1
                    }
                }

                if self.runningWorkers.loadThenWrappingDecrement(ordering: .relaxed) == 1 {
                    // the last thread that stopped notifies the thread(s) waiting for the shutdown
                    self.allThreadsStopped.offerOnce(())
                }
            }
            worker.thread = thread

            self.workers.append(worker)
        }
    }

    /// 未実行の仕事を破棄し、実行中の仕事と全スレッドの終了を待つ。
    public func shutdown() {
        if !self.stopping.exchange(true, ordering: .relaxed) {
            self.workers.removeAll()
            self.taskQueue.clear()
            self.allThreadsStopped.wait()
        }
    }

    /// Submits a task to the threadpool. The task will be asynchronously
    /// processed by one of the threads in the pool.
    ///
    /// - Parameter task: The task to be processed.
    @inlinable
    public func submit(_ task: @escaping () -> Void) {
        if !self.stopping.load(ordering: .relaxed) {
            self.taskQueue.enqueue(task)
        }
    }
}
