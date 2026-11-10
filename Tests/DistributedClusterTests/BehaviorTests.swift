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

import DistributedActorsConcurrencyHelpers
import DistributedActorsTestKit
import Foundation
import NIO
import XCTest

@testable import DistributedCluster

internal final class BehaviorTests: SingleClusterSystemXCTestCase {
    public struct TestMessage: Codable {
        internal let message: String
        internal let replyTo: ActorRef<String>
    }

    internal func testSetupExecutesImmediatelyOnStartOfActor() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("testActor-1", expecting: String.self)

        let message: String = "EHLO"
        let _: ActorRef<String> = try system.spawn(
            .anonymous,
            .setup { _ in
                probeForTest.tell(message)
                return .stop
            }
        )

        try probeForTest.expectMessage(message)
    }

    internal func testSingleActorShouldWakeUpOnNewMessageLockstep() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("testActor-2")

        var counter: Int = 0

        for _ in 0...10 {
            counter += 1
            let payload: String = "message-\(counter)"
            probeForTest.tell(payload)
            try probeForTest.expectMessage(payload)
        }
    }

    internal func testTwoActorsShouldWakeUpOnNewMessageLockstep() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("testActor-2", expecting: String.self)

        var counter: Int = 0

        let echoPayload: ActorRef<TestMessage> =
            try system.spawn(
                .anonymous,
                .receiveMessage { message in
                    probeForTest.tell(message.message)
                    return .same
                }
            )

        for _ in 0...10 {
            counter += 1
            let payload: String = "message-\(counter)"
            echoPayload.tell(TestMessage(message: payload, replyTo: probeForTest.ref))
            try probeForTest.expectMessage(payload)
        }
    }

    internal func testReceiveShouldReceiveManyMessagesInExpectedOrder() throws {
        let probeForTest: ActorTestProbe<Int> = self.testKit.makeTestProbe("testActor-3", expecting: Int.self)

        func countTillNThenDieBehavior(number: Int, currentlyAt instant: Int = -1) -> Behavior<Int> {
            if instant == number {
                return .setup { _ in
                    .stop
                }
            }
            return .receive { _, message in
                if message == instant + 1 {
                    probeForTest.tell(message)
                    return countTillNThenDieBehavior(number: number, currentlyAt: message)
                }
                fatalError("Received \(message) when was expecting \(instant + 1)! Ordering rule violated.")
            }
        }

        let number: Int = 10
        let ref: ActorRef<Int> = try system.spawn("countTill\(number)", countTillNThenDieBehavior(number: number))

        // first we send many messages
        for index in 0...number {
            ref.tell(index)
        }

        // then we expect they arrive in the expected order
        for index in 0...number {
            try probeForTest.expectMessage(index)
        }
    }

    internal func testReceiveSpecificSignalShouldReceiveAsExpected() throws {
        let probeForTest: ActorTestProbe<Signals.Terminated> = self.testKit.makeTestProbe("probe-specificSignal-1")
        let _: ActorRef<String> = try system.spawn(
            .anonymous,
            .setup { context in
                let _: ActorRef<Never> = try context.spawnWatch(.anonymous, .stop)

                return .receiveSpecificSignal(Signals.Terminated.self) { _, terminated in
                    probeForTest.tell(terminated)
                    return .stop
                }
            }
        )

        _ = try probeForTest.expectMessage()
        // receiveSignalType was invoked successfully
    }

    internal func testReceiveSpecificSignalShouldNotReceiveOtherSignals() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("probe-specificSignal-2")
        let ref: ActorRef<String> = try system.spawn(
            .anonymous,
            Behavior<String>.receiveMessage { _ in
                .stop
            }.receiveSpecificSignal(Signals.PostStop.self) { _, postStop in
                probeForTest.tell("got:\(postStop)")
                return .stop
            }
        )
        ref.tell("please stop")

        try probeForTest.expectMessage("got:PostStop()")
        // receiveSignalType was invoked successfully
    }
}
