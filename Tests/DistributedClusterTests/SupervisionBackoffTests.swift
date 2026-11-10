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

internal final class SupervisionBackoffTests: SupervisionTestCase {
    internal func assertConstantBackoffRestart(
        runName: String,
        makeEvilMessage: (String) -> FaultyMessage
    ) throws {
        let backoff: ConstantBackoffStrategy = Backoff.constant(.milliseconds(200))

        let probeForTest: ActorTestProbe<WorkerMessages> = self.testKit.makeTestProbe(expecting: WorkerMessages.self)
        let parentProbeForTest: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)

        let parentBehavior: Behavior<Never> = .setup { context in
            let _: ActorRef<FaultyMessage> = try context.spawn(
                "\(runName)-failing-2",
                self.faulty(probe: probeForTest.ref),
                props: Props().supervision(strategy: .restart(atMost: 3, within: .seconds(1), backoff: backoff))
            )

            return .same
        }
        let behavior: Behavior<Never> = parentProbeForTest.interceptAllMessages(sentTo: parentBehavior)

        let parent: ActorRef<Never> = try system.spawn("\(runName)-parent-2", behavior)
        parentProbeForTest.watch(parent)

        guard case .setupRunning(let faultyWorker) = try probeForTest.expectMessage() else {

            throw probeForTest.error()

        }
        probeForTest.watch(faultyWorker)

        func boomExpectBackoffRestart(expectedBackoff: Duration) throws {
            // confirm it is alive and working
            faultyWorker.tell(.echo(message: "one", replyTo: probeForTest.ref))
            try probeForTest.expectMessage(WorkerMessages.echo(message: "echo:one"))

            pinfo("make it crash", file: #fileID, line: #line)
            // make it crash
            faultyWorker.tell(makeEvilMessage("Boom: (\(runName))"))

            // The timing margin avoids racing the real backoff clock.
            // the racy part is: if we wait for exactly the amount of time of the backoff,
            // we may be waiting "slightly too long" and get the unexpected message;
            // we currently work around this by waiting slightly less.

            pinfo("expect no restart for \(expectedBackoff)", file: #fileID, line: #line)
            let expectedSlightlyShortedToAvoidRaces: Duration = expectedBackoff - .milliseconds(50)
            try probeForTest.expectNoMessage(for: expectedSlightlyShortedToAvoidRaces)

            // it should finally restart though
            guard case .setupRunning(let faultyWorkerRestarted) = try probeForTest.expectMessage() else {
                throw probeForTest.error()
            }
            pinfo("restarted!", file: #fileID, line: #line)

            // the `myself` ref of a restarted ref should be EXACTLY the same as the original one,
            // the actor identity remains the same
            faultyWorkerRestarted.shouldEqual(faultyWorker)
        }

        try boomExpectBackoffRestart(expectedBackoff: backoff.duration)
        try boomExpectBackoffRestart(expectedBackoff: backoff.duration)
        try boomExpectBackoffRestart(expectedBackoff: backoff.duration)
    }

    internal func assertExponentialBackoffRestart(
        runName: String,
        makeEvilMessage: (String) -> FaultyMessage
    ) throws {
        let initialInterval: Duration = .milliseconds(100)
        let multiplier: Double = 2.0
        let backoff: ExponentialBackoffStrategy = Backoff.exponential(
            initialInterval: initialInterval,
            multiplier: multiplier,
            randomFactor: 0.0
        )

        let probeForTest: ActorTestProbe<WorkerMessages> = self.testKit.makeTestProbe(expecting: WorkerMessages.self)
        let parentProbeForTest: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)

        let parentBehavior: Behavior<Never> = .setup { context in
            let _: ActorRef<FaultyMessage> = try context.spawn(
                "\(runName)-exponentialBackingOff",
                self.faulty(probe: probeForTest.ref),
                props: Props().supervision(strategy: .restart(atMost: 10, within: nil, backoff: backoff))
            )

            return .same
        }
        let behavior: Behavior<Never> = parentProbeForTest.interceptAllMessages(sentTo: parentBehavior)

        let parent: ActorRef<Never> = try system.spawn("\(runName)-parent-2", behavior)
        parentProbeForTest.watch(parent)

        guard case .setupRunning(let faultyWorker) = try probeForTest.expectMessage() else {

            throw probeForTest.error()

        }
        probeForTest.watch(faultyWorker)

        func boomExpectBackoffRestart(expectedBackoff: Duration) throws {
            // confirm it is alive and working
            faultyWorker.tell(.echo(message: "one", replyTo: probeForTest.ref))
            try probeForTest.expectMessage(WorkerMessages.echo(message: "echo:one"))

            pinfo("make it crash", file: #fileID, line: #line)
            // make it crash
            faultyWorker.tell(makeEvilMessage("Boom: (\(runName))"))

            // The timing margin avoids racing the real backoff clock.
            // the racy part is: if we wait for exactly the amount of time of the backoff,
            // we may be waiting "slightly too long" and get the unexpected message;
            // we currently work around this by waiting slightly less.

            pinfo("expect no restart for \(expectedBackoff)", file: #fileID, line: #line)
            let expectedSlightlyShortedToAvoidRaces: Duration = expectedBackoff - .milliseconds(50)
            try probeForTest.expectNoMessage(for: expectedSlightlyShortedToAvoidRaces)

            // it should finally restart though
            guard case .setupRunning(let faultyWorkerRestarted) = try probeForTest.expectMessage() else {
                throw probeForTest.error()
            }
            pinfo("restarted!", file: #fileID, line: #line)

            // the `myself` ref of a restarted ref should be EXACTLY the same as the original one,
            // the actor identity remains the same
            faultyWorkerRestarted.shouldEqual(faultyWorker)
        }

        try boomExpectBackoffRestart(expectedBackoff: .milliseconds(100))
        try boomExpectBackoffRestart(expectedBackoff: .milliseconds(200))
        try boomExpectBackoffRestart(expectedBackoff: .milliseconds(400))
    }

    internal func testRestartSupervisedThrowsShouldRestartWithConstantBackoff() throws {
        try self.assertConstantBackoffRestart(
            runName: "throws"
        ) { msg in
            FaultyMessage.pleaseThrow(error: FaultyError.boom(message: msg))
        }
    }

    internal func testRestartSupervisedThrowsShouldRestartWithExponentialBackoff() throws {
        try self.assertExponentialBackoffRestart(
            runName: "throws"
        ) { msg in
            FaultyMessage.pleaseThrow(error: FaultyError.boom(message: msg))
        }
    }
}
