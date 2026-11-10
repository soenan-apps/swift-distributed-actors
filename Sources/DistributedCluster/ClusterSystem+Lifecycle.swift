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
import Dispatch
import Distributed
import DistributedActorsConcurrencyHelpers
import Logging
import NIO
import NIOPosix

extension ClusterSystem {
    /// Suspends until the ``ClusterSystem`` is terminated by a call to ``shutdown()``.
    public var terminated: Void {
        get async throws {
            try await Shutdown(receptacle: self.shutdownReceptacle).wait()
        }
    }

    /// Returns `true` once shutdown has completed, including when it failed.
    public var isTerminated: Bool {
        self.shutdownReceptacle.isCompleted
    }

    /// Parks the current thread (usually "main thread") until the system is terminated,
    /// of the optional timeout is exceeded.
    ///
    /// This call is also offered to underlying transports which may have to perform the blocking wait themselves.
    /// Please refer to your configured transports documentation, to learn about exact semantics of parking a
    /// system while using them.
    public func park(atMost parkTimeout: Duration? = nil) throws {
        let howLongParkingMsg: String = parkTimeout.map { "for \($0.prettyDescription)" } ?? "indefinitely"
        self.log.info("Parking actor system \(howLongParkingMsg)...")

        if let maxParkingTime = parkTimeout {
            try self.shutdownReceptacle.wait(atMost: maxParkingTime)?.get()
        } else {
            try self.shutdownReceptacle.wait().get()
        }
    }

    /// Forcefully stops this actor system and all actors that live within it.
    /// This call blocks while shutting down the system's dispatchers and event loops.
    ///
    /// The returned handle and ``terminated`` expose the same completion result.
    ///
    /// - Returns: A `Shutdown` value that can be waited upon until the system has completed the shutdown.
    @discardableResult
    public func shutdown() throws -> Shutdown {
        guard self.shutdownFlag.loadThenWrappingIncrement(by: 1, ordering: .relaxed) == 0 else {
            // shutdown already kicked off by someone else
            return Shutdown(receptacle: self.shutdownReceptacle)
        }

        self.shutdownSemaphore.wait()

        // Down this node as part of shutting down; it may have enough time to notify other nodes on an best
        // effort basis.
        self.cluster.down(endpoint: self.settings.endpoint)

        let pluginsSemaphore: DispatchSemaphore = DispatchSemaphore(value: 1)
        Task {
            await self.settings.plugins.stopAll(self)
            pluginsSemaphore.signal()
        }
        pluginsSemaphore.wait()

        self.log.log(
            level: .debug,
            "Shutting down actor system [\(self.name)]. All actors will be stopped.",
            file: #filePath,
            function: #function,
            line: #line
        )
        defer {
            self.shutdownSemaphore.signal()
        }

        if let shell = self.clusterShell {
            let receptacle: BlockingReceptacle<Void> = BlockingReceptacle<Void>()
            shell.ref.tell(.command(.shutdown(receptacle)))
            receptacle.wait()
        }
        self.userProvider.stopAll()
        self.systemProvider.stopAll()
        self.dispatcher.shutdown()

        // Release system all actors
        self.releaseManagedActors()

        self.associationTombstoneCleanupTask?.cancel()
        self.associationTombstoneCleanupTask = nil

        do {
            try self.eventLoopGroup.syncShutdownGracefully()
        } catch {
            self.shutdownReceptacle.offerOnce(.failure(error))
            throw error
        }

        //     // self.serializationStorage = nil

        _ = self.clusterStore.storeIfNilThenLoad(Box(nil))

        self.shutdownReceptacle.offerOnce(.success(()))

        return Shutdown(receptacle: self.shutdownReceptacle)
    }

    private func releaseManagedActors() {
        self.initLock.withLockVoid {
            self.receptionistStore = nil
            self.downingStrategyStore = nil

            // This weird dance is because releasing distributed actors will trigger resignID,
            // which calls into the system, and also uses `namingLock` to find the actor to release.
            // We can't have it acquire the same lock, so we copy the refs out and release the last
            // references to those actors outside of the naming lock.
            var knownActors: [WellKnownName: any DistributedActor] = self.namingLock.withLock {
                self.managedWellKnownDistributedActors  // copy references
            }
            self.namingLock.withLock {
                self.managedWellKnownDistributedActors = [:]  // release
            }
            knownActors.removeAll()
        }
    }
}
