// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Cluster singleton plugin

/// Keeps at most one distributed singleton instance active in the cluster.
///
/// A singleton may run on any node in the cluster. Use `ClusterSingletonSettings.allocationStrategy` to control
/// its allocation. Use `ClusterSystem.singleton.host(type:name:factory:)` on hosting nodes.
/// Other nodes use `ClusterSystem.singleton.proxy(type:name)` to obtain a relocating proxy.
/// `DistributedActor` is a proxy that can handle situations where the singleton might get relocated to different nodes.
///
/// - Warning: Refer to the configured `AllocationStrategy` for trade-offs between safety and recovery latency for
///            the singleton allocation.
/// - SeeAlso: Erlang/OTP distributed applications and Akka cluster singletons.
public actor ClusterSingletonPlugin: Plugin {
    internal static let pluginKey: Key = "$clusterSingleton"

    private var singletons: [String: (proxyID: ActorID, boss: any ClusterSingletonBossProtocol)] = [:]

    private var actorSystem: ClusterSystem?

    nonisolated public var key: Key { Self.pluginKey }

    private var startedSystem: ClusterSystem {
        guard let system = self.actorSystem else {
            preconditionFailure("ClusterSingletonPlugin must be started before use")
        }
        return system
    }

    public init() {
        self.actorSystem = nil  // 'actorSystem' is filled in later on in Plugin.start()
    }

    /// Returns a proxy that follows the active singleton.
    public func proxy<Act>(
        _ type: Act.Type,
        name: String,
        settings: ClusterSingletonSettings = .init()
    ) async throws -> Act where Act: ClusterSingleton {
        var singletonSettings: ClusterSingletonSettings = settings
        singletonSettings.name = name
        return try await self.getSingleton(
            type, settings: singletonSettings, system: self.startedSystem, makeInstance: nil
        )
    }

    /// Configures the singleton plugin to host instances of this actor.
    public func host<Act>(
        name: String,
        settings: ClusterSingletonSettings = .init(),
        type: Act.Type = Act.self,
        makeInstance factory: (@Sendable (ClusterSystem) async throws -> Act)? = nil
    ) async throws -> Act where Act: ClusterSingleton {
        var singletonSettings: ClusterSingletonSettings = settings
        singletonSettings.name = name
        return try await self.getSingleton(
            type, settings: singletonSettings, system: self.startedSystem, makeInstance: factory
        )
    }

    internal func getSingleton<Act>(
        _ type: Act.Type,
        settings: ClusterSingletonSettings,
        system: ClusterSystem,
        makeInstance factory: (@Sendable (ClusterSystem) async throws -> Act)?
    ) async throws -> Act where Act: ClusterSingleton {
        let singletonName: String = settings.name
        guard !singletonName.isEmpty else {
            fatalError("ClusterSingleton \(Act.self) must have specified unique name!")
        }

        let known: (proxyID: ActorID, boss: any ClusterSingletonBossProtocol)? = self.singletons[singletonName]
        if let existingID = known?.proxyID {
            return try Act.resolve(id: existingID, using: system)
        }

        // Spawn the singleton boss (one per singleton per node)
        let boss: ClusterSingletonBoss<Act> = try await ClusterSingletonBoss(
            settings: settings,
            system: system,
            factory
        )
        let interceptor: ClusterSingletonRemoteCallInterceptor<Act> =
            ClusterSingletonRemoteCallInterceptor(system: system, singletonBoss: boss)
        let proxied: Act = try system.interceptCalls(to: type, metadata: ActorMetadata(), interceptor: interceptor)

        self.singletons[singletonName] = (proxied.id, boss)
        return proxied
    }

    // FOR TESTING
    internal func singletonBoss<Singleton: ClusterSingleton>(
        name: String,
        type _: Singleton.Type = Singleton.self
    ) -> ClusterSingletonBoss<Singleton>? {
        guard let (_, boss) = self.singletons[name] else {
            return nil
        }

        return boss as? ClusterSingletonBoss<Singleton>
    }
    public func start(_ system: ClusterSystem) {
        self.actorSystem = system
    }

    public func stop(_: ClusterSystem) async {
        self.actorSystem = nil
        for (_, (_, boss)) in self.singletons {
            await boss.stop()
        }
    }
}
