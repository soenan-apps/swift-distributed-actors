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

// Modified by Soenan for musl platform support.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Blocking Receptacle

/// Not intended to be used by end users.
///
/// Similar to `LinkedBlockingQueue` however specialized for a single element.
/// Used most often as "await until something happens" mechanism.
/// Can be used when no other execution context is available yet some waiting for another thread to complete some task
/// has to be performed, e.g. during dispatcher / event-loop shutdown.
///
/// Is NOT intended as a general purpose future or promise like structure,
/// it is our most modestly priced receptacle, after all.
internal final class BlockingReceptacle<Value: Sendable>: @unchecked Sendable {
    @usableFromInline internal let lock: ClusterMutex = ClusterMutex()
    @usableFromInline internal let notEmpty: ClusterCondition = ClusterCondition()

    private var storedValue: Value?
    private var asyncWaiters: Set<ClusterCancellableCheckedContinuation<Value>> = []

    internal var isCompleted: Bool {
        self.lock.synchronized { self.storedValue != nil }
    }

    /// Offer a value to the Receptacle -- only once. Further offers will result in Faults.
    ///
    /// # Warning
    /// - Faults: when offered a value a second time! This is considered a programmer error,
    ///           make sure to always correctly only offer a single value to the receptacle.
    internal func offerOnce(_ value: Value) {
        let releasedWaiters: Set<ClusterCancellableCheckedContinuation<Value>> = self.lock.synchronized {
            if self.storedValue != nil {
                fatalError(
                    """
                    BlockingReceptacle can only be offered once. Already was offered \
                    [\(self.storedValue, orElse: "no-value")] before, and can not accept new offer: [\(value)]!
                    """
                )
            }
            self.storedValue = value
            let waiters: Set<ClusterCancellableCheckedContinuation<Value>> = self.asyncWaiters
            self.asyncWaiters = []
            self.notEmpty.signalAll()
            return waiters
        }
        for waiter in releasedWaiters {
            waiter.resume(returning: value)
        }
    }

    /// Await the value to be set, or return `nil` if timeout passes and no value was set.
    internal func wait(atMost timeout: Duration) -> Value? {
        let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(timeout)
        return self.lock.synchronized { () -> Value? in
            while deadline.hasTimeLeft() {
                if let value = self.storedValue {
                    return value
                }
                _ = self.notEmpty.wait(self.lock, atMost: deadline.timeLeft)
            }
            return nil
        }
    }

    internal func wait() -> Value {
        self.lock.synchronized { () -> Value in
            while true {
                if let value = self.storedValue {
                    return value
                }
                self.notEmpty.wait(self.lock)
            }
        }
    }

    internal func wait() async throws -> Value {
        try await withClusterCancellableCheckedContinuation { waiter in
            waiter.onCancel { waiter in
                self.lock.synchronized {
                    _ = self.asyncWaiters.remove(waiter)
                }
            }
            let value: Value? = self.lock.synchronized {
                if let value = self.storedValue {
                    return value
                }
                if !waiter.isCancelled {
                    self.asyncWaiters.insert(waiter)
                }
                return nil
            }
            if let value {
                waiter.resume(returning: value)
            }
        }
    }
}

// ------------ "locks.swift" of the proposal

/// Not intended to be used by end users.
///
/// A threading lock based on `libpthread` instead of `libdispatch`.
///
/// This object provides a lock on top of a single `pthread_mutex_t`. This kind
/// of lock is safe to use with `libpthread`-based threading models, such as the
/// one used by NIO.
internal final class ReadWriteLock {
    private let rwlock: UnsafeMutablePointer<pthread_rwlock_t> = UnsafeMutablePointer.allocate(capacity: 1)

    /// Create a new lock.
    internal init() {
        let err: Int32 = pthread_rwlock_init(self.rwlock, nil)
        precondition(err == 0)
    }

    /// Acquire a reader lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `unlock`, to simplify lock handling.
    internal func lockRead() {
        let err: Int32 = pthread_rwlock_rdlock(self.rwlock)
        precondition(err == 0)
    }

    /// Acquire a writer lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `unlock`, to simplify lock handling.
    internal func lockWrite() {
        let err: Int32 = pthread_rwlock_wrlock(self.rwlock)
        precondition(err == 0)
    }

    /// Release the lock.
    ///
    /// Whenever possible, consider using `withLock` instead of this method and
    /// `lock`, to simplify lock handling.
    internal func unlock() {
        let err: Int32 = pthread_rwlock_unlock(self.rwlock)
        precondition(err == 0)
    }

    /// Acquire the reader lock for the duration of the given block.
    ///
    /// This convenience method should be preferred to `lock` and `unlock` in
    /// most situations, as it ensures that the lock will be released regardless
    /// of how `body` exits.
    ///
    /// - Parameter body: The block to execute while holding the lock.
    /// - Returns: The value returned by the block.
    @inlinable
    internal func withReaderLock<T>(_ body: () throws -> T) rethrows -> T {
        self.lockRead()
        defer {
            self.unlock()
        }
        return try body()
    }

    /// Acquire the writer lock for the duration of the given block.
    ///
    /// This convenience method should be preferred to `lock` and `unlock` in
    /// most situations, as it ensures that the lock will be released regardless
    /// of how `body` exits.
    ///
    /// - Parameter body: The block to execute while holding the lock.
    /// - Returns: The value returned by the block.
    @inlinable
    internal func withWriterLock<T>(_ body: () throws -> T) rethrows -> T {
        self.lockWrite()
        defer {
            self.unlock()
        }
        return try body()
    }

    /// reader lockの範囲内でVoidを返す処理を実行する。
    @inlinable
    internal func withReaderLockVoid(_ body: () throws -> Void) rethrows {
        try self.withReaderLock(body)
    }

    /// writer lockの範囲内でVoidを返す処理を実行する。
    @inlinable
    internal func withWriterLockVoid(_ body: () throws -> Void) rethrows {
        try self.withWriterLock(body)
    }

    deinit {
        let err: Int32 = pthread_rwlock_destroy(self.rwlock)
        precondition(err == 0)
        self.rwlock.deallocate()
    }
}

/// ユーザの直接利用を想定しない再帰的なpthread mutex。
public final class ClusterMutex {
    @usableFromInline internal var mutex: pthread_mutex_t = .init()

    /// 再帰的に取得できるmutexを初期化する。
    public init() {
        var attr: pthread_mutexattr_t = pthread_mutexattr_t()
        pthread_mutexattr_init(&attr)
        pthread_mutexattr_settype(&attr, Int32(PTHREAD_MUTEX_RECURSIVE))

        let error: Int32 = pthread_mutex_init(&self.mutex, &attr)
        pthread_mutexattr_destroy(&attr)

        switch error {
        case 0:
            return

        default:
            fatalError("Could not create mutex: \(error)")
        }
    }

    /// 現在のスレッドでmutexを取得する。
    @inlinable
    public func lock() {
        let error: Int32 = pthread_mutex_lock(&self.mutex)

        switch error {
        case 0:
            return

        case EDEADLK:
            fatalError("Mutex could not be acquired because it would have caused a deadlock")

        default:
            fatalError("Failed with unspecified error: \(error)")
        }
    }

    /// 現在のスレッドが取得したmutexを解放する。
    @inlinable
    public func unlock() {
        let error: Int32 = pthread_mutex_unlock(&self.mutex)

        switch error {
        case 0:
            return

        case EPERM:
            fatalError("Mutex could not be unlocked because it is not held by the current thread")

        default:
            fatalError("Unlock failed with unspecified error: \(error)")
        }
    }

    /// 待機せずにmutexの取得を試みる。
    @inlinable
    public func tryLock() -> Bool {
        let error: Int32 = pthread_mutex_trylock(&self.mutex)

        switch error {
        case 0:
            return true

        case EBUSY:
            return false

        case EDEADLK:
            fatalError("Mutex could not be acquired because it would have caused a deadlock")

        default:
            fatalError("Failed with unspecified error: \(error)")
        }
    }

    /// mutexを取得し、処理が返った後に解放する。
    @inlinable
    public func synchronized<A>(_ operation: () -> A) -> A {
        self.lock()

        defer {
            unlock()
        }

        return operation()
    }

    /// mutexを取得し、処理の成功・失敗にかかわらず解放する。
    @inlinable
    public func synchronized<A>(_ operation: () throws -> A) throws -> A {
        self.lock()

        defer {
            unlock()
        }

        return try operation()
    }

    deinit {
        pthread_mutex_destroy(&mutex)
    }
}
