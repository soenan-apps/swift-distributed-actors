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
import NIO
import XCTest

@testable import DistributedCluster

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

internal final class SupervisionSignalTests: SupervisionTestCase {
    internal func assertSignalFailureRestart(failBy failureMode: FailureMode) throws {
        let parentProbe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let workerProbe: ActorTestProbe<WorkerMessages> = self.testKit.makeTestProbe(expecting: WorkerMessages.self)

        // parent spawns a new child for every message it receives, the workerProbe gets the
        // reference so we can crash it then
        let parentBehavior: Behavior<String> = Behavior<String>.receive { context, _ in
            let faultyBehavior: Behavior<FaultyMessage> = self.faulty(probe: workerProbe.ref)
            try context.spawn("\(failureMode)-child", faultyBehavior)

            return .same
        }.receiveSignal { _, signal in
            if let terminated = signal as? Signals.Terminated {
                parentProbe.tell("terminated:\(terminated.id.name)")
                try failureMode.fail()
            }
            return .same
        }

        let parentRef: ActorRef<String> = try system.spawn(
            "parent",
            parentBehavior,
            props: .supervision(strategy: .restart(atMost: 2, within: nil))
        )
        parentProbe.watch(parentRef)

        parentRef.tell("spawn")
        guard case .setupRunning(let workerRef1) = try workerProbe.expectMessage() else {
            throw workerProbe.error()
        }
        workerProbe.watch(workerRef1)
        workerRef1.tell(.pleaseThrow(error: FaultyError.boom(message: "Boom inside worker.")))
        try parentProbe.expectMessage("terminated:\(failureMode)-child")
        try workerProbe.expectTerminated(workerRef1)
        try parentProbe.expectNoTerminationSignal(for: .milliseconds(50))

        pinfo("2nd child crash round", file: #fileID, line: #line)
        parentRef.tell("spawn")
        guard case .setupRunning(let workerRef2) = try workerProbe.expectMessage() else {
            throw workerProbe.error()
        }
        workerProbe.watch(workerRef2)
        workerRef2.tell(.pleaseThrow(error: FaultyError.boom(message: "Boom inside worker.")))
        try parentProbe.expectMessage("terminated:\(failureMode)-child")
        try workerProbe.expectTerminated(workerRef2)
        try parentProbe.expectNoTerminationSignal(for: .milliseconds(50))

        pinfo("3rd child crash round, parent restarts exceeded", file: #fileID, line: #line)
        parentRef.tell("spawn")
        guard case .setupRunning(let workerRef3) = try workerProbe.expectMessage() else {
            throw workerProbe.error()
        }
        workerProbe.watch(workerRef3)
        workerRef3.tell(.pleaseThrow(error: FaultyError.boom(message: "Boom inside worker.")))
        try parentProbe.expectMessage("terminated:\(failureMode)-child")
        try workerProbe.expectTerminated(workerRef3)
        try parentProbe.expectTerminated(parentRef)
    }

    internal func testThrowInSignalHandlingShouldRestart() throws {
        try self.assertSignalFailureRestart(failBy: .throwing)
    }

    internal func assertPreRestartSignal(failBy failureMode: FailureMode) throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = Behavior.receiveMessage { _ in
            try failureMode.fail()
            return .same
        }.receiveSignal { _, signal in
            if signal is Signals.PreRestart {
                probeForTest.tell("preRestart")
            }
            return .same
        }

        let ref: ActorRef<String> = try system.spawn(
            .anonymous,
            behavior,
            props: .supervision(strategy: .restart(atMost: 1, within: .seconds(5)))
        )
        probeForTest.watch(ref)

        ref.tell("test")
        try probeForTest.expectMessage("preRestart")

        ref.tell("test")
        try probeForTest.expectTerminated(ref)
    }

    internal func testSupervisorThrowsShouldCausePreRestartSignalBeforeRestarting() throws {
        try self.assertPreRestartSignal(failBy: .throwing)
    }

    internal func assertPreRestartFailureStopsActor(failBy failureMode: FailureMode, backoff: BackoffStrategy?) throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        var preRestartCounter: Int = 0

        let failOnBoom: Behavior<String> = Behavior.receiveMessage { message in
            if message == "boom" {
                try failureMode.fail()
            }
            return .same
        }.receiveSignal { _, signal in

            if signal is Signals.PreRestart {
                preRestartCounter += 1
                probeForTest.tell("preRestart-\(preRestartCounter)")
                try failureMode.fail()
                probeForTest.tell("NEVER")
            }
            return .same
        }

        let ref: ActorRef<String> = try system.spawn(
            "fail-onside-pre-restart",
            failOnBoom,
            props: .supervision(strategy: .restart(atMost: 3, within: nil, backoff: backoff))
        )
        probeForTest.watch(ref)

        ref.tell("boom")
        try probeForTest.expectMessage("preRestart-1")
        try probeForTest.expectMessage("preRestart-2")  // keep trying...
        try probeForTest.expectMessage("preRestart-3")  // last try...

        ref.tell("hello")
        try probeForTest.expectNoMessage(for: .milliseconds(100))

        try probeForTest.expectTerminated(ref)
    }

    internal func testPreRestartFailureStopsActor() throws {
        try self.assertPreRestartFailureStopsActor(failBy: .throwing, backoff: nil)
    }

    internal func testPreRestartFailureStopsActorWithBackoff() throws {
        try self.assertPreRestartFailureStopsActor(failBy: .throwing, backoff: Backoff.constant(.milliseconds(10)))
    }

    internal func testSupervisedActorShouldNotRestartedWhenCrashingInPostStop() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .receiveMessage { msg in
            probeForTest.tell("crashing:\(msg)")
            return .stop { _ in
                throw FaultyError.boom(message: "test")
            }
        }

        let ref: ActorRef<String> = try system.spawn(
            .anonymous,
            behavior,
            props: .supervision(strategy: .restart(atMost: 5, within: .seconds(5)))
        )
        probeForTest.watch(ref)

        ref.tell("test")

        try probeForTest.expectMessage("crashing:test")
        try probeForTest.expectTerminated(ref)

        ref.tell("test2")
        try probeForTest.expectNoMessage(for: .milliseconds(50))
    }
}
