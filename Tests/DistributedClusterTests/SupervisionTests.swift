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

internal final class SupervisionTests: SupervisionTestCase {
    internal func assertFailureStopsActor(runName: String, makeEvilMessage: (String) -> FaultyMessage) throws {
        let probeForTest: ActorTestProbe<WorkerMessages> = self.testKit.makeTestProbe(expecting: WorkerMessages.self)
        let parentProbeForTest: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)

        let parentBehavior: Behavior<Never> = .setup { context in
            let strategy: SupervisionStrategy = .stop
            let behavior: Behavior<FaultyMessage> = self.faulty(probe: probeForTest.ref)
            let _: ActorRef<FaultyMessage> = try context.spawn(
                "\(runName)-erroring-1",
                behavior,
                props: .supervision(strategy: strategy)
            )
            return .same
        }
        let interceptedParent: Behavior<Never> = parentProbeForTest.interceptAllMessages(sentTo: parentBehavior)

        let parent: ActorRef<Never> = try system.spawn("\(runName)-parent", interceptedParent)

        guard case .setupRunning(let faultyWorker) = try probeForTest.expectMessage() else {

            throw probeForTest.error()

        }

        probeForTest.watch(faultyWorker)
        faultyWorker.tell(makeEvilMessage("Boom"))

        // it should have stopped on the failure
        try probeForTest.expectTerminated(faultyWorker)

        // meaning that the .stop did not accidentally also cause the parent to die
        // after all, it dod NOT watch the faulty actor, so death pact also does not come into play
        parentProbeForTest.watch(parent)
        try parentProbeForTest.expectNoTerminationSignal(for: .milliseconds(100))
    }

    internal func assertRestart(runName: String, makeEvilMessage: (String) -> FaultyMessage) throws {
        let probeForTest: ActorTestProbe<WorkerMessages> = self.testKit.makeTestProbe(expecting: WorkerMessages.self)
        let parentProbeForTest: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)

        let parentBehavior: Behavior<Never> = .setup { context in
            let _: ActorRef<FaultyMessage> = try context.spawn(
                "\(runName)-erroring-2",
                self.faulty(probe: probeForTest.ref),
                props: Props().supervision(strategy: .restart(atMost: 2, within: .seconds(1)))
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

        faultyWorker.tell(.echo(message: "one", replyTo: probeForTest.ref))
        try probeForTest.expectMessage(WorkerMessages.echo(message: "echo:one"))

        faultyWorker.tell(makeEvilMessage("Boom: 1st (\(runName))"))
        try probeForTest.expectNoTerminationSignal(for: .milliseconds(300))
        try parentProbeForTest.expectNoTerminationSignal(for: .milliseconds(100))  // parent did not terminate

        pinfo("Now expecting it to run setup again...", file: #fileID, line: #line)
        guard case .setupRunning(let faultyWorkerRestarted) = try probeForTest.expectMessage() else {
            throw probeForTest.error()
        }

        // the `myself` ref of a restarted ref should be EXACTLY the same as the original one, the
        // actor identity remains the same
        faultyWorkerRestarted.shouldEqual(faultyWorker)

        pinfo("Not expecting a reply from it", file: #fileID, line: #line)
        faultyWorker.tell(.echo(message: "two", replyTo: probeForTest.ref))
        try probeForTest.expectMessage(WorkerMessages.echo(message: "echo:two"))

        faultyWorker.tell(makeEvilMessage("Boom: 2nd (\(runName))"))
        try probeForTest.expectNoTerminationSignal(for: .milliseconds(300))

        pinfo("Now it boomed but did not crash again!", file: #fileID, line: #line)
    }

    internal func testStopSupervisedThrowsShouldStop() throws {
        try self.assertFailureStopsActor(
            runName: "throws"
        ) { msg in
            FaultyMessage.pleaseThrow(error: FaultyError.boom(message: msg))
        }
    }

    internal func testStopSupervisedThrowsInAwaitResultShouldStop() throws {
        try self.assertFailureStopsActor(
            runName: "throws"
        ) { _ in
            FaultyMessage.pleaseFailAwaiting(message: "Boom!")
        }
    }

    internal func testRestartSupervisedThrowsShouldRestart() throws {
        try self.assertRestart(
            runName: "throws"
        ) { msg in
            FaultyMessage.pleaseThrow(error: FaultyError.boom(message: msg))
        }
    }

    internal func testRestartSupervisedThrowsInAwaitResultShouldRestart() throws {
        try self.assertRestart(
            runName: "throws"
        ) { _ in
            FaultyMessage.pleaseFailAwaiting(message: "Boom!")
        }
    }
}
