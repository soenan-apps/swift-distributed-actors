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

import Distributed
import DistributedActorsConcurrencyHelpers
import Foundation
import Logging

extension ClusterSystem {
    /// 指定されたIDに対応するローカルactorを解決する。
    public func resolve<Act>(id: ActorID, as _: Act.Type) throws -> Act?
    where Act: DistributedActor {
        if self.settings.logging.verboseResolve {
            self.log.trace("Resolve: \(id)")
        }

        // If it has an interceptor installed, we must pretend to resolve it as "remote",
        // though the actual messages will be delivered to the interceptor,
        // and not necessarily a remote destination.
        if let interceptor = id.context.remoteCallInterceptor {
            if self.settings.logging.verboseResolve {
                self.log.trace("Resolved \(id) as intercepted", metadata: ["interceptor": "\(interceptor)"])
            }
            return nil
        }

        // If the actor is not located on this node, immediately resolve as "remote"
        guard self.cluster.node == id.node else {
            if self.settings.logging.verboseResolve {
                self.log.trace("Resolved \(id) as remote, on node: \(id.node)")
            }
            return nil
        }

        if let wellKnownName = id.metadata.wellKnown,
            let wellKnownActor = try self.resolveWellKnownActor(id: id, name: wellKnownName, as: Act.self) {
            return wellKnownActor
        }

        // Resolve using the usual id lookup method
        let managed: (any DistributedActor)? = self.namingLock.withLock {
            self.managedDistributedActors.get(identifiedBy: id)
        }

        guard let managed = managed else {
            // TRICK: for resolveStub which we may be resolving an ID which may be dead, but we always
            // want to get the stub anyway
            if Act.self is StubDistributedActor.Type {
                return nil
            }

            throw DeadLetterError(recipient: id)
        }

        guard let resolved = managed as? Act else {
            self.log.trace(
                "Resolved actor identity, however did not match expected type: \(Act.self)",
                metadata: [
                    "actor/id": "\(id)",
                    "actor/type": "\(type(of: managed))",
                    "expected/type": "\(Act.self)",
                ]
            )
            return nil
        }

        self.log.trace(
            "Resolved as local instance",
            metadata: [
                "actor/id": "\(id)",
                "actor": "\(resolved)",
            ]
        )
        return resolved
    }

    /// 新しく作成するactorのIDを予約する。
    public func assignID<Act>(_ actorType: Act.Type) -> ClusterSystem.ActorID
    where Act: DistributedActor {
        self.assignID(actorType, baseContext: nil)
    }

    internal func assignID<Act>(
        _ actorType: Act.Type,
        baseContext: DistributedActorContext?
    ) -> ClusterSystem.ActorID
    where Act: DistributedActor {
        let props: Props = Props.forSpawn.consume()  // task-local read for any properties this actor should have

        if let designatedActorID = props.designatedActorID {
            return designatedActorID
        }

        let reservedID: ActorID
        do {
            reservedID = try self.reserveName(type: Act.self, props: props)
        } catch {
            fatalError("Unable to reserve an actor identity: \(error)")
        }
        var id: ActorID = reservedID

        let lifecycleContainer: LifecycleWatchContainer?
        if Act.self is (any (LifecycleWatch).Type) {
            lifecycleContainer = LifecycleWatchContainer(watcherID: id.withoutLifecycle, actorSystem: self)
        } else {
            lifecycleContainer = nil
        }

        //       but we're removing paths and moving them into metadata; so the reserve name should be
        // somewhat different really,
        //       but we can only do this when we remove the dependence on paths and behaviors entirely from
        // DA actors https://github.com/apple/swift-distributed-actors/issues/957
        if let context = baseContext {
            context.metadata.path = id.context.metadata.path
            assert(
                id.context.metadata.count == 1,
                "Unexpected additional metadata from reserved ID: \(id.context.metadata)"
            )
            id.context = context
        } else {
            id.context = DistributedActorContext(
                lifecycle: lifecycleContainer,
                remoteCallInterceptor: nil,
                metadata: id.context.metadata
            )
        }

        if let wellKnownName = props.wellKnownName {
            id.metadata.wellKnown = wellKnownName
            id.metadata.actorProps = PropsShuttle(props: props)
        }
        //            id.metadata.wellKnown = wellKnownName

        self.log.trace(
            "Assign identity",
            metadata: [
                "actor/type": "\(actorType)",
                "actor/id": "\(id)",
                "id": "\(id.fullDescription)",
            ]
        )

        return id
    }

    /// 初期化を終えたactorをシステムへ登録する。
    public func actorReady<Act>(_ actor: Act) where Act: DistributedActor, Act.ID == ActorID {
        self.log.trace(
            "Actor ready",
            metadata: [
                "actor/id": "\(actor.id)",
                "actor/type": "\(type(of: actor))",
            ]
        )

        self.namingLock.lock()
        defer { self.namingLock.unlock() }
        if !actor.id.isWellKnown {
            precondition(
                self.reservedNames.remove(actor.id) != nil,
                "Attempted to ready an identity that was not reserved: \(actor.id)"
            )
        }

        // Spawn a behavior actor for it:
        let behavior: Behavior<InvocationMessage> = InvocationBehavior.behavior(instance: WeakLocalRef(actor))
        let ref: ActorRef<InvocationMessage> = self.spawnDistributedActor(behavior, identifiedBy: actor.id)

        // Store references
        self.managedRefs[actor.id] = ref
        self.managedDistributedActors.insert(actor: actor)

        if let wellKnownName = actor.id.metadata.wellKnown {
            self.managedWellKnownDistributedActors[wellKnownName] = actor
        }
        for hook in self.settings.plugins.actorLifecycleHooks {
            hook.onActorReady(actor)
        }
    }

    /// Advertise to the cluster system that a "well known" distributed actor has become ready.
    /// Store it in a special lookup table and enable looking it up by its unique well-known name identity.
    public func wellKnownActorReady<Act>(_ actor: Act) where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
        self.namingLock.withLockVoid {

            guard let wellKnownName = actor.id.metadata.wellKnown else {
                preconditionFailure("Attempted to register actor as well-known but had no well-known name: \(actor.id)")
            }

            log.trace(
                "Actor ready, well-known as: \(wellKnownName)",
                metadata: [
                    "actor/id": "\(actor.id)",
                    "actor/type": "\(type(of: actor))",
                ]
            )

            self.managedWellKnownDistributedActors[wellKnownName] = actor
        }
    }

    /// Called during actor deinit/destroy.
    public func resignID(_ id: ActorID) {
        self.log.trace("Resign actor id", metadata: ["actor/id": "\(id)"])
        self.namingLock.withLockVoid {
            self.reservedNames.remove(id)
            if let ref = self.managedRefs.removeValue(forKey: id) {
                ref.sendSystemMessage(.stop, file: #filePath, line: #line)
            }
        }
        id.context.terminate()

        self.namingLock.withLockVoid {
            self.managedRefs.removeValue(forKey: id)

            // Remove the weak actor reference
            _ = self.managedDistributedActors.removeActor(identifiedBy: id)

            // Well-known actors are held strongly and should be released using `releaseWellKnownActorID`
        }
        for hook in self.settings.plugins.actorLifecycleHooks {
            hook.onResignID(id)
        }
    }

    /// 保持していたwell-known actorへの参照を解放する。
    public func releaseWellKnownActorID(_ id: ActorID) {
        guard let wellKnownName = id.metadata.wellKnown else {
            preconditionFailure(
                "Attempted to release well-known ActorID, but ID was not well known: \(id.fullDescription)"
            )
        }

        self.namingLock.withLockVoid {
            log.debug("Released well-known ActorID explicitly: \(id), it is expected to resignID soon")

            _ = self.managedWellKnownDistributedActors.removeValue(forKey: wellKnownName)
        }
    }

    private func resolveWellKnownActor<Act>(id: ActorID, name: String, as _: Act.Type) throws -> Act?
    where Act: DistributedActor {
        let registeredActor: (any DistributedActor)? = self.namingLock.withLock {
            self.managedWellKnownDistributedActors[name]
        }
        guard let registeredActor else {
            return nil
        }
        guard let typedActor = registeredActor as? Act else {
            self.log.trace(
                "Resolved local well-known instance with an unexpected type",
                metadata: [
                    "actor/id": "\(registeredActor.id)",
                    "actor/type": "\(type(of: registeredActor))",
                    "expected/type": "\(Act.self)",
                ]
            )
            throw DeadLetterError(recipient: id)
        }
        self.log.trace(
            "Resolved as local well-known instance: '\(name)",
            metadata: ["actor/id": "\(typedActor.id)"]
        )
        return typedActor
    }
}
