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
import Logging

import struct Foundation.Data
import struct Foundation.UUID

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Cluster singleton boss

/// Singleton wrapper of a distributed actor. The underlying singleton might run on this node, in which
/// case `ClusterSingletonBoss` will manage its lifecycle. Otherwise, `ClusterSingletonBoss` will act as a
/// proxy and forward calls to the remote node where the singleton is actually running. All this happens
/// automatically and is transparent to the actor holder.
///
/// `ClusterSingletonBoss` has a buffer to hold remote calls temporarily in case the singleton is not available.
/// The buffer capacity is configurable in `ClusterSingletonSettings`. Note that if the buffer becomes
/// full, the *oldest* message would be disposed to allow insertion of the latest message.
///
/// `ClusterSingletonBoss` subscribes to cluster events and feeds them into `AllocationStrategy` to
/// determine the node that the singleton runs on. If the singleton falls on *this* node, `ClusterSingletonBoss`
/// will spawn the actual singleton actor. Otherwise, `ClusterSingletonBoss` will hand over the singleton
/// whenever the node changes.
internal distributed actor ClusterSingletonBoss<Act: ClusterSingleton>: ClusterSingletonBossProtocol {
    internal typealias ActorSystem = ClusterSystem
    internal typealias CallID = UUID

    internal enum AllocationStatus {
        case allocated
        case pending
        case timedOut
    }

    @ActorID.Metadata(\.wellKnown)
    internal var wellKnownName: String

    private let settings: ClusterSingletonSettings

    /// The strategy that determines which node the singleton will be allocated.
    private let allocationStrategy: ClusterSingletonAllocationStrategy

    /// If `nil`, then this instance will be proxy-only and it will never run the actual actor.
    internal let singletonFactory: ((ClusterSystem) async throws -> Act)?

    /// The node that the singleton runs on.
    internal var targetNode: Cluster.Node?
    internal var selfNode: Cluster.Node {
        self.actorSystem.cluster.node
    }

    /// The target singleton instance we should forward invocations to.
    ///
    /// The concrete distributed actor instance (the "singleton") if this node is indeed hosting it,
    /// or nil otherwise - meaning that the singleton instance is actually located on another member.
    internal var targetSingleton: Act?

    private var allocationStatus: AllocationStatus = .pending
    private var allocationTimeoutTask: Task<Void, Error>?

    /// Remote call buffer in case `singleton` is `nil`
    private var buffer: SingletonRemoteCallBuffer<Act>

    /// `Task` for subscribing to cluster events
    private var clusterEventsSubscribeTask: Task<Void, Error>?

    internal lazy var log: Logger = Logger(actor: self)

    internal init(
        settings: ClusterSingletonSettings,
        system: ActorSystem,
        _ singletonFactory: ((ClusterSystem) async throws -> Act)?
    ) async throws {
        self.actorSystem = system
        self.settings = settings
        self.allocationStrategy = await settings.allocationStrategy.makeAllocationStrategy(
            settings: settings,
            actorSystem: system
        )
        self.singletonFactory = singletonFactory
        self.buffer = SingletonRemoteCallBuffer(capacity: settings.bufferCapacity)

        self.wellKnownName = Self.makeSingletonBossWellKnownName(settings)

        if system.settings.enabled {
            self.clusterEventsSubscribeTask = Task {
                // Subscribe to ``Cluster/Event`` in order to update `targetNode`
                for await event in system.cluster.events {
                    try await self.receiveClusterEvent(event)
                }
            }
        } else {
            // Run singleton on this node if clustering is not enabled
            self.log.debug("Clustering not enabled. Taking over singleton.")
            try await self.takeOver(from: nil)
        }
    }

    private static func makeSingletonBossWellKnownName(_ settings: ClusterSingletonSettings) -> String {
        "$singletonBoss-\(settings.name)"
    }

    private func receiveClusterEvent(_ event: Cluster.Event) async throws {
        // Feed the event to `AllocationStrategy` then forward the result to `updateTargetNode`,
        // which will determine if `targetNode` has changed and react accordingly.
        let node: Cluster.Node? = await self.allocationStrategy.onClusterEvent(event)
        try await self.updateTargetNode(node: node)
    }

    private func updateTargetNode(node: Cluster.Node?) async throws {
        guard self.targetNode != node else {
            self.log.trace(
                "Skip updating target node. New node is already the same as current targetNode.",
                metadata: self.metadata()
            )
            return
        }

        let previousTargetNode: Cluster.Node? = self.targetNode
        self.targetNode = node

        switch node {
        case selfNode:
            try await self.takeOver(from: previousTargetNode)

        default:
            if previousTargetNode == selfNode {
                self.handOver(to: node)
            }

            // Update `singleton` regardless
            try await self.updateSingleton(node: node)
        }
    }

    private func takeOver(from: Cluster.Node?) async throws {
        guard let singletonFactory = self.singletonFactory else {
            preconditionFailure(
                "Cluster singleton [\(self.settings.name)] cannot run on this node. "
                    + "Please review SingletonAllocationSettings and/or cluster singleton usage."
            )
        }

        self.log.debug(
            "Take over singleton [\(self.settings.name)] from [\(String(describing: from))]",
            metadata: self.metadata()
        )

        if let existing = self.targetSingleton {
            self.log.warning(
                """
                Singleton taking over from \(String(describing: from)), however local active instance \
                already available: \(existing) (\(existing.id)). This is suspicious, \
                we should have only activated the instance once we became active.
                """
            )
            return
        }

        let singleton: Act = try await self.activate(singletonFactory)
        self.updateSingleton(singleton)
    }

    internal func handOver(to nextNode: Cluster.Node?) {
        guard let instance = self.targetSingleton else {
            return  // we're done, we never allocated it at all
        }

        self.log.debug(
            "Hand over singleton [\(self.settings.name)] to [\(String(describing: nextNode))]",
            metadata: self.metadata()
        )

        Task {
            // we ask the singleton to passivate, it may want to flush some writes or similar.
            await instance.whenLocal { [log] localInstance in
                log.debug("Passivating singleton \(instance.id)...")
                await localInstance.passivateSingleton()
            }

            // Release the local instance after it has completed passivation.
            self.actorSystem.releaseWellKnownActorID(instance.id)
            self.updateSingleton(nil)
        }
    }

    /// Update on which ``Cluster/Node`` this boss considers the singleton to be hosted.
    internal func updateSingleton(node: Cluster.Node?) async throws {
        switch node {
        case .some(let node) where node == self.actorSystem.cluster.node:
            // This must have been a result of an activate() and the singleton must be stored locally
            precondition(self.targetSingleton?.id.node == self.actorSystem.cluster.node)
            return

        case .some(let otherNode):
            var targetSingletonBossID: ActorID = ActorID(remote: otherNode, type: Self.self, incarnation: .wellKnown)
            targetSingletonBossID.metadata.wellKnown = Self.makeSingletonBossWellKnownName(self.settings)
            targetSingletonBossID.path = self.id.path
            let targetSingletonBoss: ClusterSingletonBoss<Act> =
                try Self.resolve(id: targetSingletonBossID, using: self.actorSystem)

            let locatedSingleton: Act = try await Backoff.exponential(
                initialInterval: settings.locateActiveSingletonBackoff.initialInterval,
                multiplier: settings.locateActiveSingletonBackoff.multiplier,
                capInterval: settings.locateActiveSingletonBackoff.capInterval,
                randomFactor: settings.locateActiveSingletonBackoff.randomFactor,
                maxAttempts: settings.locateActiveSingletonBackoff.maxAttempts
            ).attempt {
                // confirm tha the boss is hosting the singleton, if not we may have to wait and try again
                do {
                    guard (try? await targetSingletonBoss.hasActiveSingleton()) ?? false else {
                        throw SingletonNotFoundNoExpectedNode(id: self.settings.name, node)
                    }
                } catch {
                    throw error
                }

                var targetSingletonID: ActorID = ActorID(remote: otherNode, type: Self.self, incarnation: .wellKnown)
                targetSingletonID.metadata.wellKnown = self.settings.name
                targetSingletonID.path = self.id.path

                return try Act.resolve(id: targetSingletonID, using: self.actorSystem)
            }
            self.updateSingleton(locatedSingleton)

        case .none:
            self.updateSingleton(nil)
        }
    }

    // Returns Bool because returning generic Act? cannot currently be encoded (swift#67090).
    internal distributed func hasActiveSingleton() -> Bool {
        guard let targetSingleton = self.targetSingleton else {
            self.log.debug("Was checked for active singleton. Not active.")
            return false
        }
        guard targetSingleton.id.node == self.selfNode else {
            self.log.debug("Was checked for active singleton. Active on different node.")
            return false
        }
        self.log.debug("Was checked for active singleton. Active on this node.")
        return true
    }

    private func updateSingleton(_ newSingleton: Act?) {
        self.log.debug(
            """
            Update singleton from [\(String(describing: self.targetSingleton))] \
            to [\(newSingleton?.id.description ?? "nil")], with \(self.buffer.count) remote calls pending
            """,
            metadata: self.metadata()
        )
        self.targetSingleton = newSingleton

        // Unstash messages if we have the singleton
        guard let singleton = newSingleton else {
            self.allocationStatus = .pending
            self.startTimeoutTask()
            return
        }

        self.allocationStatus = .allocated
        self.allocationTimeoutTask?.cancel()
        self.allocationTimeoutTask = nil

        if !buffer.isEmpty {
            self.log.debug(
                "Flushing \(buffer.count) remote calls to [\(Act.self)] on [\(singleton.id.node)]",
                metadata: self.metadata()
            )
            while let (_, continuation) = self.buffer.take() {
                continuation.resume(returning: singleton)
            }
        }
    }

    private func activate(_ singletonFactory: (ClusterSystem) async throws -> Act) async throws -> Act {
        let props: Props = Props.singletonInstance(settings: self.settings)
        let singleton: Act = try await Props.$forSpawn.withValue(props) {
            try await singletonFactory(self.actorSystem)
        }

        await singleton.whenLocal { localSingleton in
            await localSingleton.activateSingleton()
        }

        self.log.trace("Activated singleton instance: \(singleton.id.fullDescription)", metadata: self.metadata())
        assert(
            singleton.id.metadata.wellKnown == self.settings.name,
            "Singleton instance assigned ID is not well-known, but should be"
        )

        return singleton
    }

    nonisolated internal func stop() async {
        await self.whenLocal { localBoss in
            localBoss.handOver(to: nil)
        }
    }

    internal func metadata(_ extra: [String: String] = [:]) -> Logger.Metadata {
        var metadata: Logger.Metadata = [
            "singleton/name": "\(self.settings.name)",
            "singleton/type": "\(Act.self)",
            "singleton/buffer": "\(self.buffer.count)/\(self.buffer.capacity)",
        ]
        metadata["target/node"] = "\(String(describing: self.targetNode?.debugDescription ?? "nil"))"
        if let singleton = self.targetSingleton {
            metadata["target/id"] = "\(singleton.id)"
        }
        for (key, value) in extra {
            metadata[key] = "\(value)"
        }
        return metadata
    }

    deinit {
        self.clusterEventsSubscribeTask?.cancel()
    }
}

extension ClusterSingletonBoss {
    internal func findSingleton(target: RemoteCallTarget) async throws -> Act {
        guard self.allocationStatus != .timedOut else {
            throw ClusterSingletonError.allocationTimeout
        }

        // If singleton is available, forward remote call to it right away.
        if let singleton = self.targetSingleton {
            return singleton
        }

        // Otherwise, we "stash" the remote call until singleton becomes available.
        let found: Act = try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let callID: UUID = UUID()
                    try self.buffer.stash((callID, continuation))
                    self.log.debug(
                        "Stashed remote call [\(callID)] to [\(target)]",
                        metadata: self.metadata([
                            "remoteCall/target": "\(target)"
                        ])
                    )
                } catch {
                    switch error {
                    case SingletonBufferError.full:
                        self.log.warning(
                            "Buffer is full. Remote call might start getting disposed.",
                            metadata: self.metadata()
                        )
                        if let oldest = self.buffer.take() {
                            oldest.continuation.resume(throwing: ClusterSingletonError.bufferCapacityExceeded)
                        }

                    default:
                        self.log.warning("Unable to stash remote call, error: \(error)", metadata: self.metadata())
                        continuation.resume(throwing: ClusterSingletonError.stashFailure)
                    }
                }
            }
        }

        log.info("Found singleton: \(found) local:\(__isLocalActor(found))", metadata: self.metadata())
        return found
    }

    private func startTimeoutTask() {
        self.allocationTimeoutTask = Task {
            try await Task.sleep(until: .now + self.settings.allocationTimeout, clock: .continuous)

            guard !Task.isCancelled else {
                return
            }

            self.allocationStatus = .timedOut
        }
    }
}
