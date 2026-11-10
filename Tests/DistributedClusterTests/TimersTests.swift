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

internal final class TimersTests: SingleClusterSystemXCTestCase {
    internal func testTimerKey_shouldPrintNicely() {
        TimerKey("Hello").description.shouldEqual("TimerKey(Hello)")
        TimerKey("Hello", isSystemTimer: true).description.shouldEqual("TimerKey(Hello, isSystemTimer: true)")
    }

    internal func test_startSingleTimer_shouldSendSingleMessage() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            context.timers.startSingle(key: TimerKey("message"), message: "fromTimer", delay: .microseconds(100))
            return .receiveMessage { message in
                probeForTest.tell(message)
                return .same
            }
        }

        try system.spawn(.anonymous, behavior)
        try probeForTest.expectMessage("fromTimer")
        try probeForTest.expectNoMessage(for: .milliseconds(10))
    }

    internal func test_startPeriodicTimer_shouldSendPeriodicMessage() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            var index: Int = 0
            context.timers.startPeriodic(key: TimerKey("message"), message: "fromTimer", interval: .milliseconds(10))
            return .receiveMessage { message in
                index += 1
                probeForTest.tell(message)

                if index >= 5 {
                    return .stop
                }
                return .same
            }
        }

        try system.spawn(.anonymous, behavior)
        for _ in 0..<5 {
            try probeForTest.expectMessage("fromTimer")
        }
        try probeForTest.expectNoMessage(for: .milliseconds(10))
    }

    internal func test_periodicTimer_shouldStopWhenCanceled() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            var index: Int = 0
            context.timers.startPeriodic(key: TimerKey("message"), message: "fromTimer", interval: .milliseconds(10))
            return .receiveMessage { message in
                index += 1
                probeForTest.tell(message)

                if index >= 5 {
                    context.timers.cancel(for: TimerKey("message"))
                }
                return .same
            }
        }

        try system.spawn(.anonymous, behavior)
        for _ in 0..<5 {
            try probeForTest.expectMessage("fromTimer")
        }
        try probeForTest.expectNoMessage(for: .milliseconds(100))
    }

    internal func test_singleTimer_shouldStopWhenCanceled() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = Behavior<String>.setup { context in
            // We start the timer without delay and then sleep for a short
            // amount of time, so the timer is triggered and sends the message.
            // Because we cancel the timer in the same run, the message should
            // not be processed and the probe should not receive a message.
            context.timers.startSingle(key: TimerKey("message"), message: "fromTimer", delay: .nanoseconds(0))
            DistributedCluster.ClusterThread.sleep(.milliseconds(10))  // replace with Task.sleep
            context.timers.cancel(for: TimerKey("message"))
            return .receiveMessage { message in
                probeForTest.tell(message)
                return .same
            }
        }

        _ = try self.system.spawn(.anonymous, behavior)
        try probeForTest.expectNoMessage(for: .milliseconds(10))
    }

    internal func test_timers_cancelAllShouldStopAllTimers() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            context.timers.startPeriodic(key: TimerKey("message"), message: "fromTimer", interval: .milliseconds(10))
            context.timers.startPeriodic(key: TimerKey("message2"), message: "fromTimer2", interval: .milliseconds(50))
            context.timers.startPeriodic(key: TimerKey("message3"), message: "fromTimer3", interval: .milliseconds(50))
            return .receiveMessage { message in
                probeForTest.tell(message)
                context.timers.cancelAll()
                return .same
            }
        }

        try system.spawn(.anonymous, behavior)
        try probeForTest.expectMessage("fromTimer")
        try probeForTest.expectNoMessage(for: .milliseconds(100))
    }

    internal func test_timers_cancelAllShouldNotStopSystemTimers() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            context.timers.startPeriodic(
                key: TimerKey("message", isSystemTimer: true),
                message: "fromSystemTimer",
                interval: .milliseconds(10)
            )
            return .receiveMessage { message in
                probeForTest.tell(message)
                context.timers.cancelAll()
                return .same
            }
        }

        try system.spawn(.anonymous, behavior)
        try probeForTest.expectMessage("fromSystemTimer")
        try probeForTest.expectMessage("fromSystemTimer")
        try probeForTest.expectMessage("fromSystemTimer")
        try probeForTest.expectMessage("fromSystemTimer")
    }
}
