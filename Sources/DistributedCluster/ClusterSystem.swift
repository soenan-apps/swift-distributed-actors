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
import Backtrace
import Dispatch
@_exported import Distributed
import DistributedActorsConcurrencyHelpers
import Foundation
import Logging
import NIO
import NIOPosix

/// A confined space that runs and manages distributed actors until shutdown.
public class ClusterSystem: DistributedActorSystem, @unchecked Sendable {
    public typealias InvocationDecoder = ClusterInvocationDecoder
    public typealias InvocationEncoder = ClusterInvocationEncoder
    /// Codable準拠はisolation domainをまたいで使用できる必要がある。
    /// 値自体のSendable準拠は要求しない。
    public typealias SerializationRequirement = any Codable & SendableMetatype
    public typealias ResultHandler = ClusterInvocationResultHandler
    public typealias CallID = UUID
    internal typealias WellKnownName = String

    internal final class Box<T> {
        internal var value: T

        internal init(_ value: T) {
            self.value = value
        }
    }

    /// Object that can be awaited on until the system has completed shutting down.
    public struct Shutdown {
        private let receptacle: BlockingReceptacle<Result<Void, Error>>

        internal init(receptacle: BlockingReceptacle<Result<Void, Error>>) {
            self.receptacle = receptacle
        }

        @available(*, deprecated, message: "will be replaced by distributed actor / closure version")
        public func wait(atMost timeout: Duration) throws {
            try self.receptacle.wait(atMost: timeout)?.get()
        }

        @available(*, deprecated, message: "will be replaced by distributed actor / closure version")
        public func wait() throws {
            try self.receptacle.wait().get()
        }

        /// Suspend until the system has completed its shutdown and is terminated.
        public func wait() async throws {
            try await self.receptacle.wait().get()
        }
    }

    #if SACT_TESTS_LEAKS
    internal static let actorSystemInitCounter: ManagedAtomic<Int> = .init(0)
    #endif

    public let name: String
    /// Immutable settings used to configure this system.
    public let settings: ClusterSystemSettings
    /// Root logger configured by the system's logging settings.
    public let log: Logger
    /// Event-loop group owned by this system.
    public let eventLoopGroup: MultiThreadedEventLoopGroup
    internal var deadLettersStorage: ActorRef<DeadLetter>?
    internal var namingContext: ActorNamingContext = ActorNamingContext()
    internal let namingLock: Lock = Lock()
    internal let initLock: Lock = Lock()
    internal var associationTombstoneCleanupTask: RepeatedTask?
    internal let dispatcher: InternalMessageDispatcher
    internal var managedRefs: [ActorID: ReceivesSystemMessages] = [:]
    internal var managedDistributedActors: WeakAnyDistributedActorDictionary = .init()
    internal var reservedNames: Set<ActorID> = []
    internal var managedWellKnownDistributedActors: [WellKnownName: any DistributedActor] = [:]
    internal var systemProviderStorage: ActorRefProvider?
    internal var userProviderStorage: ActorRefProvider?
    internal let root: ReceivesSystemMessages
    internal let lazyInitializationLock: ReadWriteLock
    internal var serializationStorage: ManagedAtomicLazyReference<Serialization>
    internal let inFlightCallLock: Lock = Lock()
    internal var inFlightCalls: [CallID: CheckedContinuation<any AnyRemoteCallReply, Error>] = [:]
    internal var receptionistRef: ManagedAtomicLazyReference<Box<ActorRef<Receptionist.Message>>>
    internal var receptionistStore: OpLogDistributedReceptionist?
    internal let metrics: ClusterSystemMetrics
    internal let clusterStore: ManagedAtomicLazyReference<Box<ClusterShell?>>
    internal let clusterControlStore: ManagedAtomicLazyReference<Box<ClusterControl>>
    internal let nodeDeathWatcherStore: ManagedAtomicLazyReference<Box<NodeDeathWatcherShell.Ref?>>
    internal var downingStrategyStore: DowningStrategyShell?
    internal let shutdownReceptacle: BlockingReceptacle<Result<Void, Error>> = BlockingReceptacle()
    internal let shutdownSemaphore: DispatchSemaphore = DispatchSemaphore(value: 1)
    internal let shutdownFlag: ManagedAtomic<Int> = .init(0)

    #if SACT_TESTS_LEAKS
    internal let userCellInitCounter: ManagedAtomic<Int> = .init(0)
    internal let userMailboxInitCounter: ManagedAtomic<Int> = .init(0)
    #endif

    internal var deadLettersRef: ActorRef<DeadLetter> {
        guard let reference = self.deadLettersStorage else {
            preconditionFailure("Dead letters are accessed before system startup")
        }
        return reference
    }

    internal var systemProvider: ActorRefProvider {
        guard let provider = self.systemProviderStorage else {
            preconditionFailure("System actor provider is accessed before system startup")
        }
        return provider
    }

    internal var userProvider: ActorRefProvider {
        guard let provider = self.userProviderStorage else {
            preconditionFailure("User actor provider is accessed before system startup")
        }
        return provider
    }

    /// Serialization configured during synchronous system startup.
    public var serialization: Serialization {
        self.lazyInitializationLock.withReaderLock {
            guard let storedSerialization = self.serializationStorage.load() else {
                return fatalErrorBacktrace(
                    "Serialization is not initialized during system startup"
                )
            }
            return storedSerialization
        }
    }

    internal var actorRefReceptionist: SystemReceptionist {
        guard let ref = self.receptionistRef.load()?.value else {
            self.initLock.lock()
            defer { self.initLock.unlock() }
            return self.actorRefReceptionist
        }
        return SystemReceptionist(ref: ref)
    }

    /// Receptionist for registering and discovering distributed actors.
    public var receptionist: OpLogDistributedReceptionist {
        self.initLock.lock()
        defer { self.initLock.unlock() }
        guard let storedReceptionist = self.receptionistStore else {
            preconditionFailure("Receptionist is accessed before system startup")
        }
        return storedReceptionist
    }

    internal var clusterShell: ClusterShell? {
        guard let box = self.clusterStore.load() else {
            self.initLock.lock()
            defer { self.initLock.unlock() }
            return self.clusterShell
        }
        return box.value
    }

    /// Control interface for cluster membership and events.
    public var cluster: ClusterControl {
        guard let box = self.clusterControlStore.load() else {
            self.initLock.lock()
            defer { self.initLock.unlock() }
            return self.cluster
        }
        return box.value
    }

    internal var nodeDeathWatcher: NodeDeathWatcherShell.Ref? {
        guard let box = self.nodeDeathWatcherStore.load() else {
            self.initLock.lock()
            defer { self.initLock.unlock() }
            return self.nodeDeathWatcher
        }
        return box.value
    }

    internal var downing: DowningStrategyShell? {
        self.initLock.lock()
        defer { self.initLock.unlock() }
        return self.downingStrategyStore
    }

    internal var isShuttingDown: Bool {
        self.shutdownFlag.load(ordering: .sequentiallyConsistent) > 0
    }

    /// Creates a named `ClusterSystem`.
    /// The name is useful for debugging cross system communication.
    ///
    /// - Faults: when configuration closure performs very illegal action, e.g. reusing a serializer identifier
    public convenience init(
        _ name: String,
        configuredWith configureSettings: sending (inout ClusterSystemSettings) -> Void = { _ in () }
    ) async {
        var configuredSettings: ClusterSystemSettings = ClusterSystemSettings(name: name)
        configureSettings(&configuredSettings)

        await self.init(settings: configuredSettings)
    }

    /// Creates a named `ClusterSystem`.
    /// The passed in name is going to override the setting's cluster node name.
    ///
    /// - Faults: when configuration closure performs very illegal action, e.g. reusing a serializer identifier
    public convenience init(_ name: String, settings: ClusterSystemSettings) async {
        var namedSettings: ClusterSystemSettings = settings
        namedSettings.endpoint.systemName = name
        await self.init(settings: namedSettings)
    }

    /// Creates a `ClusterSystem` using the passed in settings.
    ///
    /// - Faults: when configuration closure performs very illegal action, e.g. reusing a serializer identifier
    public init(settings initialSettings: ClusterSystemSettings) async {
        var configuredSettings: ClusterSystemSettings = initialSettings
        self.name = configuredSettings.endpoint.systemName

        let loopGroup: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(
            numberOfThreads: configuredSettings.threadPoolSize
        )
        configuredSettings.eventLoopGroup = loopGroup

        self.eventLoopGroup = loopGroup

        do {
            self.dispatcher = try FixedThreadPool(configuredSettings.threadPoolSize)
        } catch {
            fatalError("Unable to initialize the actor dispatcher: \(error)")
        }

        // initialize top level guardians
        self.root = TheOneWhoHasNoParent(local: configuredSettings.bindNode)

        self.lazyInitializationLock = ReadWriteLock()

        if !configuredSettings.logging.customizedLogger {
            // Copy the log level that has been set on the initial logger before we replace it
            let desiredLogLevel: Logger.Level = configuredSettings.logging.loggerStorage.logLevel
            configuredSettings.logging.loggerStorage = Logger(label: self.name)
            configuredSettings.logging.loggerStorage.logLevel = desiredLogLevel
        }

        if configuredSettings.enabled {
            configuredSettings.logging.loggerStorage[metadataKey: "cluster/node"] = "\(configuredSettings.bindNode)"
        } else {
            configuredSettings.logging.loggerStorage[metadataKey: "cluster/node"] = "\(self.name)"
        }

        self.settings = configuredSettings
        self.log = configuredSettings.logging.baseLogger
        self.metrics = ClusterSystemMetrics(configuredSettings.metrics)

        self.receptionistRef = ManagedAtomicLazyReference()
        self.serializationStorage = ManagedAtomicLazyReference()
        self.clusterStore = ManagedAtomicLazyReference()
        self.clusterControlStore = ManagedAtomicLazyReference()
        self.nodeDeathWatcherStore = ManagedAtomicLazyReference()

        do {
            try await self.startServices()
        } catch {
            fatalError("Unable to start actor system services: \(error)")
        }
    }

    public convenience init() async {
        await self.init("ClusterSystem")
    }

    /// Creates a `ClusterSystem` using the passed in optional settings.
    public convenience init(settings: ClusterSystemSettings?) async {
        if let settings {
            await self.init(settings: settings)
        } else {
            await self.init()
        }
    }

    internal func withNamingContext<T>(_ block: (inout ActorNamingContext) throws -> T) rethrows -> T {
        try self.namingLock.withLock {
            try block(&self.namingContext)
        }
    }

    deinit {

        #if SACT_TESTS_LEAKS
        Self.actorSystemInitCounter.loadThenWrappingDecrement(ordering: .relaxed)

        #endif
    }

}
