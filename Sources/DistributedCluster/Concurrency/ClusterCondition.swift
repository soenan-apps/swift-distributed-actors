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

import NIO

// Modified by Soenan for musl platform support.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Not intended for general use.
public final class ClusterCondition {
    @usableFromInline internal var condition: pthread_cond_t = .init()

    /// pthreadの条件変数を初期化する。
    public init() {
        let error: Int32 = pthread_cond_init(&self.condition, nil)

        switch error {
        case 0:
            return

        default:
            fatalError("Condition could not be created: \(error)")
        }
    }

    /// mutexを解放して通知を待ち、復帰前に再取得する。
    @inlinable
    public func wait(_ mutex: ClusterMutex) {
        let error: Int32 = pthread_cond_wait(&self.condition, &mutex.mutex)

        switch error {
        case 0:
            return

        case EPERM:
            fatalError("Wait failed, mutex is not owned by this thread")

        case EINVAL:
            fatalError("Wait failed, condition is not valid")

        default:
            fatalError("Wait failed with unspecified error: \(error)")
        }
    }

    /// 指定時間まで待ち、通知で復帰した場合はtrueを返す。
    @inlinable
    public func wait(_ mutex: ClusterMutex, atMost duration: Duration) -> Bool {
        #if canImport(Darwin)
        let time: timespec = TimeSpec.from(duration: duration)
        #else
        var now: timespec = timespec()
        clock_gettime(CLOCK_REALTIME, &now)
        let time: timespec = now + TimeSpec.from(duration: duration)
        #endif
        let error: Int32 = withUnsafePointer(to: time) { timePointer -> Int32 in
            #if canImport(Darwin)
            return pthread_cond_timedwait_relative_np(&condition, &mutex.mutex, timePointer)
            #else
            return pthread_cond_timedwait(&condition, &mutex.mutex, timePointer)
            #endif
        }

        switch error {
        case 0:
            return true

        case ETIMEDOUT:
            return false

        case EPERM:
            fatalError("Wait failed, mutex is not owned by this thread")

        case EINVAL:
            fatalError("Wait failed, condition is not valid")

        default:
            fatalError("Wait failed with unspecified error: \(error)")
        }
    }

    /// 待機しているスレッドを一つ起こす。
    @inlinable
    public func signal() {
        let error: Int32 = pthread_cond_signal(&self.condition)

        switch error {
        case 0:
            return

        case EINVAL:
            fatalError("Signal failed, condition is not valid")

        default:
            fatalError("Signal failed with unspecified error: \(error)")
        }
    }

    /// 待機しているすべてのスレッドを起こす。
    @inlinable
    public func signalAll() {
        let error: Int32 = pthread_cond_broadcast(&self.condition)

        switch error {
        case 0:
            return

        case EINVAL:
            fatalError("Signal failed, condition is not valid")

        default:
            fatalError("Signal failed with unspecified error: \(error)")
        }
    }

    deinit {
        pthread_cond_destroy(&condition)
    }
}
