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
import DistributedActorsTestKit
import Foundation
import XCTest

@testable import DistributedCluster

internal final class WorkerPoolTests: SingleClusterSystemXCTestCase {
    internal func test_workerPool_registerNewlyStartedActors() async throws {
        let workerKey: DistributedReception.Key<WorkerPoolGreeter> =
            DistributedReception.Key(WorkerPoolGreeter.self, id: "request-workers")

        let settings: WorkerPoolSettings<WorkerPoolGreeter> =
            WorkerPoolSettings(selector: .dynamic(workerKey), strategy: .simpleRoundRobin)
        let workers: WorkerPool<WorkerPoolGreeter> = try await WorkerPool(settings: settings, actorSystem: system)

        let probeA: ActorTestProbe<String> = self.testKit.makeTestProbe("pA")
        let probeB: ActorTestProbe<String> = self.testKit.makeTestProbe("pB")
        let probeC: ActorTestProbe<String> = self.testKit.makeTestProbe("pC")

        let workerA: WorkerPoolGreeter =
            await WorkerPoolGreeter(probe: probeA, actorSystem: self.system, key: workerKey)
        let workerB: WorkerPoolGreeter =
            await WorkerPoolGreeter(probe: probeB, actorSystem: self.system, key: workerKey)
        let workerC: WorkerPoolGreeter =
            await WorkerPoolGreeter(probe: probeC, actorSystem: self.system, key: workerKey)

        let workerProbes: [ClusterSystem.ActorID: ActorTestProbe<String>] = [
            workerA.id: probeA,
            workerB.id: probeB,
            workerC.id: probeC,
        ]
        let workerIDs: [ActorID] = [workerA.id, workerB.id, workerC.id]

        // Wait for all workers to be registered with the receptionist
        try await waitForPoolSize(workers, expected: workerProbes.count)

        // Submit work with all workers available
        try await assertRoundRobin(
            workers,
            ids: workerIDs,
            probes: workerProbes,
            prefix: "",
            indices: 0...7
        )
    }

    internal func test_workerPool_dynamic_removeDeadActors() async throws {
        let workerKey: DistributedReception.Key<WorkerPoolGreeter> =
            DistributedReception.Key(WorkerPoolGreeter.self, id: "request-workers")

        let workers: WorkerPool<WorkerPoolGreeter> = try await WorkerPool(
            settings: .init(selector: .dynamic(workerKey), strategy: .simpleRoundRobin),
            actorSystem: system
        )

        let probeA: ActorTestProbe<String> = self.testKit.makeTestProbe("pA")
        let probeB: ActorTestProbe<String> = self.testKit.makeTestProbe("pB")
        let probeC: ActorTestProbe<String> = self.testKit.makeTestProbe("pC")

        var workerA: WorkerPoolGreeter? =
            await WorkerPoolGreeter(probe: probeA, actorSystem: self.system, key: workerKey)
        var workerB: WorkerPoolGreeter? =
            await WorkerPoolGreeter(probe: probeB, actorSystem: self.system, key: workerKey)
        var workerC: WorkerPoolGreeter? =
            await WorkerPoolGreeter(probe: probeC, actorSystem: self.system, key: workerKey)

        let workerAID: ActorID = try XCTUnwrap(workerA).id
        let workerBID: ActorID = try XCTUnwrap(workerB).id
        let workerCID: ActorID = try XCTUnwrap(workerC).id

        let workerProbes: [ClusterSystem.ActorID: ActorTestProbe<String>] = [
            workerAID: probeA,
            workerBID: probeB,
            workerCID: probeC,
        ]
        var workerIDs: [ActorID] = [workerAID, workerBID, workerCID]

        // Wait for all workers to be registered with the receptionist
        try await waitForPoolSize(workers, expected: workerProbes.count)

        // Submit work with all workers available
        try await assertRoundRobin(
            workers,
            ids: workerIDs,
            probes: workerProbes,
            prefix: "all-available-",
            indices: 0...2
        )

        // Terminate workerA
        workerIDs.removeAll { $0 == workerAID }
        workerA = nil
        try probeA.expectMessage("Greeter deinit")

        // The remaining workers should take over
        try await assertSurvivingWorkersReceive(
            workers,
            workerIDs: workerIDs,
            probes: workerProbes
        )

        // Terminate the rest of the workers
        workerB = nil
        try probeB.expectMessage("Greeter deinit")
        workerC = nil
        try probeC.expectMessage("Greeter deinit")

        // Register new worker
        let probeD: ActorTestProbe<String> = self.testKit.makeTestProbe("pD")
        let workerD: WorkerPoolGreeter =
            await WorkerPoolGreeter(probe: probeD, actorSystem: self.system, key: workerKey)

        // WorkerPool should wait for D to join then assign work to it
        _ = try await workers.submit(work: "D-only")
        try probeD.expectMessage("work:D-only at \(workerD.id)")
    }

    internal func test_workerPool_static_removeDeadActors_throwErrorWhenNoWorkers() async throws {
        let probeA: ActorTestProbe<String> = self.testKit.makeTestProbe("pA")
        let probeB: ActorTestProbe<String> = self.testKit.makeTestProbe("pB")
        let probeC: ActorTestProbe<String> = self.testKit.makeTestProbe("pC")

        var workerA: WorkerPoolGreeter? = WorkerPoolGreeter(probe: probeA, actorSystem: self.system)
        var workerB: WorkerPoolGreeter? = WorkerPoolGreeter(probe: probeB, actorSystem: self.system)
        var workerC: WorkerPoolGreeter? = WorkerPoolGreeter(probe: probeC, actorSystem: self.system)

        let workerAID: ActorID = try XCTUnwrap(workerA).id
        let workerBID: ActorID = try XCTUnwrap(workerB).id
        let workerCID: ActorID = try XCTUnwrap(workerC).id

        var workers: [WorkerPoolGreeter] = try [XCTUnwrap(workerA), XCTUnwrap(workerB), XCTUnwrap(workerC)]
        let workerIDs: [ActorID] = workers.map(\.id)

        let workerPool: WorkerPool<WorkerPoolGreeter> = try await WorkerPool(
            settings: .init(
                selector: .static(workers),
                strategy: .simpleRoundRobin
            ),
            actorSystem: system
        )

        let workerProbes: [ClusterSystem.ActorID: ActorTestProbe<String>] = [
            workerAID: probeA,
            workerBID: probeB,
            workerCID: probeC,
        ]

        // Submit work with all workers available
        try await assertRoundRobin(
            workerPool,
            ids: workerIDs,
            probes: workerProbes,
            prefix: "all-available-",
            indices: 0...2
        )

        // Terminate workerA
        workers.removeFirst()
        workerA = nil
        try probeA.expectMessage("Greeter deinit")

        // The remaining workers should take over
        try await assertSurvivingWorkersReceive(
            workerPool,
            workerIDs: workerIDs,
            probes: workerProbes
        )

        // Terminate the rest of the workers
        workers.removeFirst()
        workerB = nil
        try probeB.expectMessage("Greeter deinit")
        workers.removeFirst()
        workerC = nil
        try probeC.expectMessage("Greeter deinit")

        // WorkerPool now throws error on new work submission
        try await assertStaticPoolExhausted(workerPool)
    }

    internal func test_workerPool_static_throwOnEmptyInitialSet() async throws {
        let error: any Error = try await shouldThrow {
            let _: WorkerPool<WorkerPoolGreeter> = try await WorkerPool(selector: .static([]), actorSystem: system)
        }

        guard let workerPoolError = error as? WorkerPoolError,
            case .emptyStaticWorkerPool(let errorMessage) = workerPoolError.underlying.error
        else {
            throw testKit.fail("Expected WorkerPoolError.emptyStaticWorkerPool, got \(error)")
        }
        errorMessage.shouldContain("Illegal empty collection passed to `.static` worker pool")
    }

    internal func test_workerPool_testRemoteActorReferencesAreHandledProperly() async throws {
        let (local, remote): (ClusterSystem, ClusterSystem) = await self.setUpPair { settings in
            settings.enabled = true
        }
        let testKit: ActorTestKit = ActorTestKit(local)
        try await self.joinNodes(node: local, with: remote)

        let workerKey: DistributedReception.Key<WorkerPoolGreeter> =
            DistributedReception.Key<WorkerPoolGreeter>(id: "request-workers")
        let workers: WorkerPool<WorkerPoolGreeter> = try await WorkerPool(
            settings: WorkerPoolSettings(
                selector: .dynamic(workerKey),
                strategy: .simpleRoundRobin
            ),
            actorSystem: local
        )
        let probeA: ActorTestProbe<String> = testKit.makeTestProbe("pA")
        let probeB: ActorTestProbe<String> = testKit.makeTestProbe("pB")
        let probeC: ActorTestProbe<String> = testKit.makeTestProbe("pC")

        let workerA: WorkerPoolGreeter = await WorkerPoolGreeter(probe: probeA, actorSystem: remote, key: workerKey)
        let workerB: WorkerPoolGreeter = await WorkerPoolGreeter(probe: probeB, actorSystem: remote, key: workerKey)
        let workerC: WorkerPoolGreeter = await WorkerPoolGreeter(probe: probeC, actorSystem: remote, key: workerKey)

        let workerProbes: [ClusterSystem.ActorID: ActorTestProbe<String>] = [
            workerA.id: probeA,
            workerB.id: probeB,
            workerC.id: probeC,
        ]
        let workerIDs: [ActorID] = [workerA.id, workerB.id, workerC.id]

        // Wait for all workers to be registered with the receptionist
        try await waitForPoolSize(workers, expected: workerProbes.count)

        // Submit work with all workers available
        try await assertRoundRobin(
            workers,
            ids: workerIDs,
            probes: workerProbes,
            prefix: "",
            indices: 0...7
        )
    }
}
