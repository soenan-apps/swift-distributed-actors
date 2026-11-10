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

// Modified by Soenan for musl platform support.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A `Lock` with a built-in state variable.
///
/// This class provides a convenience addition to `Lock`: it provides the ability to wait
/// until the state variable is set to a specific value to acquire the lock.
public final class ConditionLock<T: Equatable> {
    private var _value: T
    private let mutex: Lock
    private let cond: UnsafeMutablePointer<pthread_cond_t> = UnsafeMutablePointer.allocate(capacity: 1)

    /// The value of the state variable.
    ///
    /// Obtaining the value of the state variable requires acquiring the lock.
    /// This means that it is not safe to access this property while holding the
    /// lock: it is only safe to use it when not holding it.
    public var value: T {
        self.lock()
        defer {
            self.unlock()
        }
        return self._value
    }

    /// Create the lock, and initialize the state variable to `value`.
    ///
    /// - Parameter value: The initial value to give the state variable.
    public init(value: T) {
        self._value = value
        self.mutex = Lock()
        let err: Int32 = pthread_cond_init(self.cond, nil)
        precondition(err == 0, "\(#function) failed in pthread_mutex with error \(err)")
    }

    /// Acquire the lock, regardless of the value of the state variable.
    public func lock() {
        self.mutex.lock()
    }

    /// Release the lock, regardless of the value of the state variable.
    public func unlock() {
        self.mutex.unlock()
    }

    /// Acquire the lock when the state variable is equal to `wantedValue`.
    ///
    /// - Parameter wantedValue: The value to wait for the state variable
    ///     to have before acquiring the lock.
    public func lock(whenValue wantedValue: T) {
        self.lock()
        while true {
            if self._value == wantedValue {
                break
            }
            let err: Int32 = pthread_cond_wait(self.cond, self.mutex.mutex)
            precondition(err == 0, "\(#function) failed in pthread_cond with error \(err)")
        }
    }

    /// Acquire the lock when the state variable is equal to `wantedValue`,
    /// waiting no more than `timeoutSeconds` seconds.
    ///
    /// - Parameter wantedValue: The value to wait for the state variable
    ///     to have before acquiring the lock.
    /// - Parameter timeoutSeconds: The number of seconds to wait to acquire
    ///     the lock before giving up.
    /// - Returns: `true` if the lock was acquired, `false` if the wait timed out.
    public func lock(whenValue wantedValue: T, timeoutSeconds: Double) -> Bool {
        precondition(timeoutSeconds >= 0)

        let nsecPerSec: Int64 = 1_000_000_000
        self.lock()
        // the timeout as a (seconds, nano seconds) pair
        let timeoutNS: Int64 = Int64(timeoutSeconds * Double(nsecPerSec))

        var curTime: timeval = timeval()
        gettimeofday(&curTime, nil)

        let allNSecs: Int64 = timeoutNS + Int64(curTime.tv_usec) * 1_000
        var timeoutAbs: timespec = timespec(
            tv_sec: curTime.tv_sec + Int(allNSecs / nsecPerSec),
            tv_nsec: Int(allNSecs % nsecPerSec)
        )
        assert(timeoutAbs.tv_nsec >= 0 && timeoutAbs.tv_nsec < Int(nsecPerSec))
        assert(timeoutAbs.tv_sec >= curTime.tv_sec)
        while true {
            if self._value == wantedValue {
                return true
            }
            switch pthread_cond_timedwait(self.cond, self.mutex.mutex, &timeoutAbs) {
            case 0:
                continue

            case ETIMEDOUT:
                self.unlock()
                return false

            case let errorCode:
                fatalError("caught error \(errorCode) when calling pthread_cond_timedwait")
            }
        }
    }

    /// Release the lock, setting the state variable to `newValue`.
    ///
    /// - Parameter newValue: The value to give to the state variable when we
    ///     release the lock.
    public func unlock(withValue newValue: T) {
        self._value = newValue
        self.unlock()
        let err: Int32 = pthread_cond_broadcast(self.cond)
        precondition(err == 0, "\(#function) failed in pthread_cond with error \(err)")
    }

    deinit {
        let err: Int32 = pthread_cond_destroy(self.cond)
        precondition(err == 0, "\(#function) failed in pthread_mutex with error \(err)")
        self.cond.deallocate()
    }

}
