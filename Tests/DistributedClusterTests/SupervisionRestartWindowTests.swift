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

internal final class SupervisionRestartWindowTests: SupervisionTestCase {
    internal func assertRestartLimitWithinPeriod(runName: String, makeEvilMessage: (String) -> FaultyMessage) throws {
        let probeForTest: ActorTestProbe<WorkerMessages> = self.testKit.makeTestProbe(expecting: WorkerMessages.self)
        let parentProbeForTest: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)

        let failurePeriod: Duration = .seconds(1)  // .milliseconds(300)

        let parentBehavior: Behavior<Never> = .setup { context in
            let _: ActorRef<FaultyMessage> = try context.spawn(
                "\(runName)-erroring-within-2",
                self.faulty(probe: probeForTest.ref),
                props: .supervision(strategy: .restart(atMost: 2, within: failurePeriod))
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

        try assertRestartWindow(
            worker: faultyWorker,
            probe: probeForTest,
            parentProbe: parentProbeForTest,
            window: (runName: runName, period: failurePeriod),
            makeEvilMessage: makeEvilMessage
        )
    }

    internal func testRestartAtMostWithinThrowsShouldRestartNoMoreThanAllowedWithinPeriod() throws {
        try self.assertRestartLimitWithinPeriod(
            runName: "throws"
        ) { msg in
            FaultyMessage.pleaseThrow(error: FaultyError.boom(message: msg))
        }
    }

    private func assertRestartWindow(
        worker: ActorRef<FaultyMessage>,
        probe: ActorTestProbe<WorkerMessages>,
        parentProbe: ActorTestProbe<Never>,
        window: (runName: String, period: Duration),
        makeEvilMessage: (String) -> FaultyMessage
    ) throws {
        worker.tell(.echo(message: "one", replyTo: probe.ref))
        try probe.expectMessage(WorkerMessages.echo(message: "echo:one"))

        pinfo("1st boom...", file: #fileID, line: #line)
        worker.tell(makeEvilMessage("Boom: 1st (\(window.runName))"))
        try probe.expectNoTerminationSignal(for: .milliseconds(30))
        try parentProbe.expectNoTerminationSignal(for: .milliseconds(10))  // parent did not terminate
        guard case .setupRunning = try probe.expectMessage() else {
            throw probe.error()
        }

        pinfo(
            "\(Date()) :: Giving enough breathing time to replenish the restart period (\(window.period))",
            file: #fileID,
            line: #line
        )
        ClusterThread.sleep(window.period)
        pinfo("\(Date()) :: Done sleeping...", file: #fileID, line: #line)

        pinfo("2nd boom...", file: #fileID, line: #line)
        worker.tell(makeEvilMessage("Boom: 2nd period, 1st failure in period (2nd total) (\(window.runName))"))
        try probe.expectNoTerminationSignal(for: .milliseconds(30))
        try parentProbe.expectNoTerminationSignal(for: .milliseconds(10))  // parent did not terminate
        guard case .setupRunning = try probe.expectMessage() else {
            throw probe.error()
        }

        pinfo("3rd boom...", file: #fileID, line: #line)
        // cause another failure right away -- meaning in this period we are up to 2/2 failures
        worker.tell(makeEvilMessage("Boom: 2nd period, 2nd failure in period (3rd total) (\(window.runName))"))
        try probe.expectNoTerminationSignal(for: .milliseconds(30))
        try parentProbe.expectNoTerminationSignal(for: .milliseconds(10))  // parent did not terminate

        pinfo("4th boom...", file: #fileID, line: #line)
        worker.tell(makeEvilMessage("Boom: 2nd period, 3rd failure in period (4th total) (\(window.runName))"))
        try probe.expectTerminated(worker)
        try parentProbe.expectNoTerminationSignal(for: .milliseconds(10))  // parent did not terminate
        guard case .setupRunning = try probe.expectMessage() else {
            throw probe.error()
        }

        pinfo("Now it boomed but did not crash again!", file: #fileID, line: #line)
    }
}
