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

import Atomics
import DistributedActorsConcurrencyHelpers
import NIO

// Modified by Soenan for musl imports and pointer-based pthread_t.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Not intended for general use.
internal enum ThreadError: Error {
    case threadCreationFailed
    case threadJoinFailed
}

private class BoxedClosure {
    let body: () -> Void

    init(body: @escaping () -> Void) {
        self.body = body
    }
}

/// Owns a detached pthread and supports cancellation while its operation is running.
public class ClusterThread {
    #if os(Linux)
    internal typealias CRunnerCallback = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    #else
    internal typealias CRunnerCallback = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    #endif

    internal static var runnerCallback: CRunnerCallback {
        { arg in
            let unmanaged: Unmanaged<BoxedClosure>
            #if os(Linux)
            guard let arg else {
                preconditionFailure("Thread callback requires its retained closure")
            }
            unmanaged = Unmanaged<BoxedClosure>.fromOpaque(arg)
            #else
            unmanaged = Unmanaged<BoxedClosure>.fromOpaque(arg)
            #endif
            defer { unmanaged.release() }
            unmanaged.takeUnretainedValue().body()

            return nil
        }
    }

    private let thread: pthread_t
    private let lock: ClusterMutex
    private var isRunning: ManagedAtomic<Bool>

    /// Starts a detached thread that executes the supplied operation once.
    public init(_ operation: @escaping () -> Void) throws {
        let threadLock: ClusterMutex = ClusterMutex()
        let runningState: ManagedAtomic<Bool> = ManagedAtomic<Bool>(true)
        let ref: Unmanaged<BoxedClosure> = Unmanaged.passRetained(
            BoxedClosure {
                defer {
                    threadLock.synchronized {
                        runningState.store(false, ordering: .relaxed)
                    }
                }
                operation()
            }
        )

        #if canImport(Glibc)
        var createdThread: pthread_t = pthread_t()
        #else
        var createdThread: pthread_t?
        #endif

        guard pthread_create(&createdThread, nil, Self.runnerCallback, ref.toOpaque()) == 0 else {
            ref.release()
            throw ThreadError.threadCreationFailed
        }

        #if canImport(Glibc)
        self.thread = createdThread
        #else
        guard let createdThread else {
            preconditionFailure("pthread_create succeeded without returning a thread")
        }
        self.thread = createdThread
        #endif
        self.isRunning = runningState
        self.lock = threadLock

        // we detach to free all of its resources without another thread having to join it
        pthread_detach(self.thread)
    }

    /// Suspends the current thread for the supplied duration.
    public static func sleep(_ duration: Duration) {
        var time: timespec = TimeSpec.from(duration: duration)
        let err: Int32 = nanosleep(&time, nil)
        if err != 0 {
            switch errno {
            case EFAULT:
                fatalError("Sleep failed because the information could not be copied")

            case EINVAL:
                fatalError("Sleep failed because of invalid data")

            case EINTR:
                fatalError("Sleep failed because fo an interrupt")

            default:
                fatalError("Sleep failed with unspecified error: \(err)")
            }
        }
    }

    /// Terminates the current thread with the supplied exit code.
    public static func exit(code: inout Int) {
        pthread_exit(&code)
    }

    /// Requests cancellation if the detached thread is still running.
    public func cancel() {
        self.lock.synchronized {
            if self.isRunning.load(ordering: .relaxed) {
                let error: Int32 = pthread_cancel(self.thread)

                switch error {
                case 0:
                    return

                case ESRCH:
                    fatalError("Cancel failed because no thread could be found with id: \(self.thread)")

                default:
                    fatalError("Cancel failed with unspecified error: \(error)")
                }
            }
        }
    }
}
