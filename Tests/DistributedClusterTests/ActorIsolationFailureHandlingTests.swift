// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
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
import Logging
import XCTest

@testable import DistributedCluster

internal final class ActorIsolationFailureHandlingTests: SingleClusterSystemXCTestCase {
    private enum SimpleTestError: Error {
        case simpleError(reason: String)
    }

    internal enum SimpleProbeMessage: Equatable, NotActuallyCodableMessage {
        case spawned(child: ActorRef<FaultyWorkerMessage>)
        case echoing(message: String)
    }

    internal enum FaultyWorkerMessage: NotActuallyCodableMessage {
        case work(number: Int, divideBy: Int)
        case throwError(error: Error)
    }

    internal enum WorkerError: Error {
        case error(code: Int)
    }

    internal let spawnFaultyWorkerCommand: String = "spawnFaultyWorker"

    internal func faultyWorkerBehavior(probe workerProbe: ActorRef<Int>) -> Behavior<FaultyWorkerMessage> {
        .receive { context, message in
            context.log.info("Working on: \(message)")
            switch message {
            case let .work(number, divideBy):  // Fault handling is not implemented
                workerProbe.tell(number / divideBy)
                return .same

            case .throwError(let error):
                context.log.warning("Throwing as instructed, error: \(error)")
                throw error
            }
        }
    }

    internal func healthyBossBehavior(
        messageProbe: ActorRef<SimpleProbeMessage>,
        workerProbe: ActorRef<Int>
    ) -> Behavior<String> {
        .receive { context, message in
            switch message {
            case self.spawnFaultyWorkerCommand:
                let worker: ActorRef<FaultyWorkerMessage> = try context.spawn(
                    "faultyWorker",
                    self.faultyWorkerBehavior(probe: workerProbe)
                )
                messageProbe.tell(.spawned(child: worker))

            default:
                messageProbe.tell(.echoing(message: message))
            }
            return .same
        }
    }

    internal func test_worker_crashOnlyWorkerOnPlainErrorThrow() throws {
        let messageProbe: ActorTestProbe<SimpleProbeMessage> = self.testKit.makeTestProbe("testProbe-boss-1")
        let workerProbe: ActorTestProbe<Int> = self.testKit.makeTestProbe("testProbeForWorker-1")

        let healthyBoss: ActorRef<String> = try system.spawn(
            "healthyBoss",
            self.healthyBossBehavior(
                messageProbe: messageProbe.ref,
                workerProbe: workerProbe.ref
            )
        )

        // watch parent and see it spawn the worker:
        messageProbe.watch(healthyBoss)
        healthyBoss.tell("spawnFaultyWorker")
        guard case .spawned(let worker) = try messageProbe.expectMessage() else { throw messageProbe.error() }

        // watch the worker and see that it works correctly:
        workerProbe.watch(worker)
        worker.tell(.work(number: 100, divideBy: 10))
        try workerProbe.expectMessage(10)

        // issue a message that will cause the worker to crash
        worker.tell(.throwError(error: WorkerError.error(code: 418)))  // BOOM!

        // the worker, should have terminated due to the error:
        try workerProbe.expectTerminated(worker)

        // even though the worker crashed, the parent is still alive (!)
        let stillAlive: String = "still alive"
        healthyBoss.tell(stillAlive)
        try messageProbe.expectMessage(.echoing(message: "still alive"))
    }
}
