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

/// A threading lock based on `libpthread` instead of `libdispatch`.
///
/// This object provides a lock on top of a single `pthread_mutex_t`. This kind
/// of lock is safe to use with `libpthread`-based threading models, such as the
/// one used by NIO.
@available(*, noasync, message: "Locks are bad in async code; If you truly must, use DispatchSemaphore")
public final class Lock {
    internal let mutex: UnsafeMutablePointer<pthread_mutex_t> = UnsafeMutablePointer.allocate(capacity: 1)

    /// Create a new lock.
    public init() {
        var attr: pthread_mutexattr_t = pthread_mutexattr_t()
        pthread_mutexattr_init(&attr)
        pthread_mutexattr_settype(&attr, .init(PTHREAD_MUTEX_ERRORCHECK))

        let err: Int32 = pthread_mutex_init(self.mutex, &attr)
        precondition(err == 0, "\(#function) failed in pthread_mutex with error \(err)")
    }

    /// Acquire the lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `unlock`, to simplify lock handling.
    public func lock() {
        let err: Int32 = pthread_mutex_lock(self.mutex)
        if err != 0 {
            fatalError("\(#function) failed in pthread_mutex with error \(err)")
        }
    }

    /// Release the lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `lock`, to simplify lock handling.
    public func unlock() {
        let err: Int32 = pthread_mutex_unlock(self.mutex)
        precondition(err == 0, "\(#function) failed in pthread_mutex with error \(err)")
    }

    /// Acquire the lock for the duration of the given block.
    ///
    /// This convenience method should be preferred to `lock` and `unlock` in
    /// most situations, as it ensures that the lock will be released regardless
    /// of how `body` exits.
    ///
    /// - Parameter body: The block to execute while holding the lock.
    /// - Returns: The value returned by the block.
    @inlinable
    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return try body()
    }

    /// Executes a throwing Void-returning operation while holding the lock.
    @inlinable
    public func withLockVoid(_ body: () throws -> Void) rethrows {
        try self.withLock(body)
    }
    deinit {
        let err: Int32 = pthread_mutex_destroy(self.mutex)
        precondition(err == 0, "\(#function) failed in pthread_mutex with error \(err)")
        mutex.deallocate()
    }

}
