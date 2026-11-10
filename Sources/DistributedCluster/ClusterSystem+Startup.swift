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
import Distributed
import DistributedActorsConcurrencyHelpers
import Foundation
import Logging
import NIO

extension ClusterSystem {
    internal func startServices() async throws {
        self.initLock.lock()
        defer { self.initLock.unlock() }

        try self.installActorProviders()
        let lazyNodeDeathWatcher: LazyStart<NodeDeathWatcherShell.Message>? = try await self.startClusterServices()
        let receptionistBehavior: Behavior<Receptionist.Message> = self.settings.receptionist.behavior(
            settings: self.settings
        )
        let lazyReceptionist: LazyStart<Receptionist.Message> = try self.prepareSystemActor(
            Receptionist.naming,
            receptionistBehavior,
            props: .wellKnown
        )
        _ = self.receptionistRef.storeIfNilThenLoad(Box(lazyReceptionist.ref))

        await Props.$forSpawn.withValue(OpLogDistributedReceptionist.props) {
            let distributedReceptionist: OpLogDistributedReceptionist = await OpLogDistributedReceptionist(
                settings: self.settings.receptionist,
                system: self
            )
            self.receptionistStore = distributedReceptionist
        }

        if self.settings.enabled {
            await Props.$forSpawn.withValue(DowningStrategyShell.props) {
                if let downingStrategy = self.settings.downingStrategy.make(self.settings) {
                    self.downingStrategyStore = await DowningStrategyShell(downingStrategy, system: self)
                }
            }
        } else {
            self.downingStrategyStore = nil
        }

        #if SACT_TESTS_LEAKS
        _ = Self.actorSystemInitCounter.loadThenWrappingIncrement(ordering: .relaxed)
        #endif

        // Publish every startup dependency before waking the delayed actors.
        _ = self.metrics
        lazyReceptionist.wakeUp()
        lazyNodeDeathWatcher?.wakeUp()
        await self.settings.plugins.startAll(self)
        self.logStartup()
    }

    internal func installActorProviders() throws {
        let configuredSettings: ClusterSystemSettings = self.settings
        let serializer: Serialization = try Serialization(settings: configuredSettings, system: self)
        _ = self.serializationStorage.storeIfNilThenLoad(serializer)
        self.deadLettersStorage = ActorRef(
            .deadLetters(.init(self.log, id: ActorID.deadLettersRef(on: configuredSettings.bindNode), system: self))
        )
        let localUserProvider: LocalActorRefProvider = LocalActorRefProvider(
            root: Guardian(parent: self.root, name: "user", localNode: configuredSettings.bindNode, system: self)
        )
        let localSystemProvider: LocalActorRefProvider = LocalActorRefProvider(
            root: Guardian(parent: self.root, name: "system", localNode: configuredSettings.bindNode, system: self)
        )
        var effectiveUserProvider: ActorRefProvider = localUserProvider
        var effectiveSystemProvider: ActorRefProvider = localSystemProvider
        if configuredSettings.enabled {
            let shell: ClusterShell = ClusterShell(settings: configuredSettings)
            _ = self.clusterStore.storeIfNilThenLoad(Box(shell))
            effectiveUserProvider = RemoteActorRefProvider(
                settings: configuredSettings, cluster: shell, localProvider: localUserProvider
            )
            effectiveSystemProvider = RemoteActorRefProvider(
                settings: configuredSettings, cluster: shell, localProvider: localSystemProvider
            )
        }
        self.lazyInitializationLock.withWriterLockVoid {
            self.systemProviderStorage = effectiveSystemProvider
            self.userProviderStorage = effectiveUserProvider
        }
        if !configuredSettings.enabled {
            let clusterEvents: ClusterEventStream = ClusterEventStream(self)
            _ = self.clusterStore.storeIfNilThenLoad(Box(nil))
            _ = self.clusterControlStore.storeIfNilThenLoad(
                Box(
                    ClusterControl(
                        configuredSettings,
                        cluster: nil,
                        clusterRef: self.deadLetters.adapted(),
                        eventStream: clusterEvents
                    )
                )
            )
        }
    }

    internal func startClusterServices() async throws -> LazyStart<NodeDeathWatcherShell.Message>? {
        guard let shell = self.clusterShell else {
            _ = self.nodeDeathWatcherStore.storeIfNilThenLoad(Box(nil))
            return nil
        }
        let clusterEvents: ClusterEventStream = ClusterEventStream(self)
        let clusterRef: ActorRef<ClusterShell.Message> = try await shell.start(
            system: self,
            clusterEvents: clusterEvents
        )
        _ = self.clusterControlStore.storeIfNilThenLoad(
            Box(ClusterControl(self.settings, cluster: shell, clusterRef: clusterRef, eventStream: clusterEvents))
        )
        self.associationTombstoneCleanupTask = self.eventLoopGroup.next().scheduleRepeatedTask(
            initialDelay: self.settings.associationTombstoneCleanupInterval.toNIO,
            delay: self.settings.associationTombstoneCleanupInterval.toNIO
        ) { _ in
            clusterRef.tell(.command(.cleanUpAssociationTombstones))
        }
        let lazyWatcher: LazyStart<NodeDeathWatcherShell.Message> = try self.prepareSystemActor(
            NodeDeathWatcherShell.naming,
            NodeDeathWatcherShell.behavior(clusterEvents: clusterEvents),
            props: .wellKnown
        )
        _ = self.nodeDeathWatcherStore.storeIfNilThenLoad(Box(lazyWatcher.ref))
        return lazyWatcher
    }

    internal func logStartup() {
        if self.settings.enabled {
            self.log.info(
                "ClusterSystem [\(self.name)] initialized, listening on: \(self.settings.bindNode): \(self.cluster.ref)"
            )

            self.log.info("Setting in effect: .autoLeaderElection: \(self.settings.autoLeaderElection)")
            self.log.info("Setting in effect: .downingStrategy: \(self.settings.downingStrategy)")
            self.log.info("Setting in effect: .onDownAction: \(self.settings.onDownAction)")
        } else {
            self.log.info("ClusterSystem [\(self.name)] initialized; Cluster disabled, not listening for connections.")
        }
    }
}
