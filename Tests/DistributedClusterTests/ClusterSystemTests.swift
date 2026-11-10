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

import DistributedActorsTestKit
import Foundation
import XCTest

@testable import DistributedCluster

internal final class ClusterSystemTests: SingleClusterSystemXCTestCase {
    internal let maxSpecialTreatedValueTypeSizeInBytes: Int = 24

    internal func test_system_spawn_shouldThrowOnDuplicateName() throws {
        let _: ActorRef<String> = try system.spawn("test", .ignore)

        let error: Error = try shouldThrow {
            let _: ActorRef<String> = try system.spawn("test", .ignore)
        }

        guard let systemError = error as? ClusterSystemError, case .duplicateActorPath(let path, _) =
            systemError.underlying.error else {
            XCTFail("Expected ClusterSystemError.duplicateActorPath, but was: \(error)")
            return
        }

        let expected: ActorPath = try ActorPath(root: "user") / ActorPathSegment("test")
        path.shouldEqual(expected)
    }

    internal func test_system_spawn_shouldNotThrowOnNameReUse() throws {
        let probe: ActorTestProbe<Int> = self.testKit.makeTestProbe()
        // re-using a name of an actor that has been stopped is fine
        let ref: ActorRef<String> = try system.spawn("test", .stop)

        probe.watch(ref)
        try probe.expectTerminated(ref)

        // since spawning on top level is racy for the names replacements;
        // we try a few times, and if it eventually succeeds things are correct -- it should succeed only once though
        try self.testKit.eventually(within: .milliseconds(500)) {
            let _: ActorRef<String> = try system.spawn("test", .ignore)
        }
    }

    internal func test_shutdown_shouldStopAllActors() async throws {
        let system2: ClusterSystem = await ClusterSystem("ShutdownSystem")
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let echoBehavior: Behavior<String> = .receiveMessage { message in
            probe.tell(message)
            return .same
        }

        let ref1: ActorRef<String> = try system2.spawn(.anonymous, echoBehavior)
        let ref2: ActorRef<String> = try system2.spawn(.anonymous, echoBehavior)

        probe.watch(ref1)
        probe.watch(ref2)

        try await system2.shutdown().wait()

        try probe.expectTerminatedInAnyOrder([ref1.asAddressable, ref2.asAddressable])

        ref1.tell("ref1")
        ref2.tell("ref2")

        try probe.expectNoMessage(for: .milliseconds(200))
    }

    internal func test_shutdown_shouldCompleteReturnedHandleWhenDone() async throws {
        let shutdown: ClusterSystem.Shutdown = try system.shutdown()
        try await shutdown.wait()
    }

    internal func test_shutdown_shouldReUseReceptacleWhenCalledMultipleTimes() async throws {
        let system2: ClusterSystem = await ClusterSystem("ShutdownSystem")
        let shutdown1: ClusterSystem.Shutdown = try system2.shutdown()
        let shutdown2: ClusterSystem.Shutdown = try system2.shutdown()
        let shutdown3: ClusterSystem.Shutdown = try system2.shutdown()

        try await shutdown1.wait()
        try await shutdown2.wait()
        try await shutdown3.wait()
    }

    internal func test_shutdown_selfSendingActorShouldNotDeadlockSystem() async throws {
        let system2: ClusterSystem = await ClusterSystem("ShutdownSystem")
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let echoBehavior: Behavior<String> = .receive { context, message in
            context.myself.tell(message)
            return .same
        }

        let selfSender: ActorRef<String> = try system2.spawn(.anonymous, echoBehavior)

        probe.watch(selfSender)

        try await system2.shutdown().wait()

        try probe.expectTerminated(selfSender)
    }

    internal func test_terminated_triggerOnceSystemIsShutdown() async throws {
        let system2: ClusterSystem = await ClusterSystem("ShutdownSystem") { closureArgument in
            closureArgument.enabled = false  // no clustering
        }

        _ = try system2.shutdown()

        try await system2.terminated  // should be terminated after shutdown()
    }

    internal func test_shutdownWait_triggerOnceSystemIsShutdown() async throws {
        let system2: ClusterSystem = await ClusterSystem("ShutdownSystem") { closureArgument in
            closureArgument.enabled = false  // no clustering
        }

        try await system2.shutdown().wait()
    }

    internal func test_resolveUnknownActor_shouldReturnPersonalDeadLetters() throws {
        let path: ActorPath = try ActorPath.userRoot.appending("test").appending("foo").appending("bar")
        let id: ActorID = ActorID(local: self.system.cluster.node, path: path, incarnation: .random())
        let context: ResolveContext<Never> = ResolveContext(id: id, system: self.system)
        let ref: ActorRef<Never> = self.system.resolve(context: context)

        ref.id.path.shouldEqual(ActorPath.dead.appending(segments: path.segments))
        ref.id.incarnation.shouldEqual(id.incarnation)
    }

    // https://github.com/apple/swift-distributed-actors/issues/1196
    internal func disabledAssociationTombstoneCleanup() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.enabled = true
            settings.associationTombstoneTTL = .seconds(0)
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.enabled = true
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let remoteAssociationControlState0: ClusterShell.StoredAssociationState = try XCTUnwrap(
            local.clusterShell
        ).getEnsureAssociation(with: remote.cluster.node)
        guard case ClusterShell.StoredAssociationState.association(let remoteControl0) =
            remoteAssociationControlState0 else {
            throw Boom("Expected the association to exist for \(remote.cluster.node)")
        }

        ClusterShell.shootTheOtherNodeAndCloseConnection(system: local, targetNodeAssociation: remoteControl0)

        // Endpoint should eventually appear in tombstones
        try self.testKit(local).eventually(within: .seconds(3)) {
            guard local.clusterShell?.testingAssociationTombstones.isEmpty == false else {
                throw Boom("Expected tombstone for downed node")
            }
        }

        local.clusterShell?.ref.tell(.command(.cleanUpAssociationTombstones))

        try self.testKit(local).eventually(within: .seconds(3)) {
            guard local.clusterShell?.testingAssociationTombstones.isEmpty == true else {
                throw Boom("Expected tombstones to get cleared")
            }
        }
    }
}
