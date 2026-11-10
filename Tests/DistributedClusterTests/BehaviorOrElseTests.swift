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

internal final class BehaviorOrElseTests: SingleClusterSystemXCTestCase {
    internal enum OrElseMessage: String, Codable {
        case first = "first"
        case second = "second"
        case other = "other"
    }

    internal func firstBehavior(_ probe: ActorRef<OrElseMessage>) -> Behavior<OrElseMessage> {
        .receiveMessage { message in
            switch message {
            case .first:
                probe.tell(.first)
                return .same

            case .second:
                return .unhandled

            default:
                return .ignore
            }
        }
    }

    internal func secondBehavior(_ probe: ActorRef<OrElseMessage>) -> Behavior<OrElseMessage> {
        .receiveMessage { message in
            probe.tell(message)
            return .same
        }
    }

    internal func combinedBehavior(_ probe: ActorRef<OrElseMessage>) -> Behavior<OrElseMessage> {
        self.firstBehavior(probe).orElse(self.secondBehavior(probe))
    }

    internal func testOrElseShouldExecuteFirstBehavior() throws {
        let probeForTest: ActorTestProbe<OrElseMessage> = self.testKit.makeTestProbe()
        let ref: ActorRef<OrElseMessage> = try system.spawn(.anonymous, self.combinedBehavior(probeForTest.ref))

        ref.tell(.first)
        try probeForTest.expectMessage(.first)
    }

    internal func testOrElseShouldExecuteSecondBehavior() throws {
        let probeForTest: ActorTestProbe<OrElseMessage> = self.testKit.makeTestProbe()
        let ref: ActorRef<OrElseMessage> = try system.spawn(.anonymous, self.combinedBehavior(probeForTest.ref))

        ref.tell(.second)
        try probeForTest.expectMessage(.second)
    }

    internal func testOrElseShouldNotExecuteSecondBehaviorOnIgnore() throws {
        let probeForTest: ActorTestProbe<OrElseMessage> = self.testKit.makeTestProbe()
        let ref: ActorRef<OrElseMessage> = try system.spawn(.anonymous, self.combinedBehavior(probeForTest.ref))

        ref.tell(.other)
        try probeForTest.expectNoMessage(for: .milliseconds(100))
    }

    internal func testOrElseShouldProperlyHandleDeeplyNestedBehaviors() throws {
        let probeForTest: ActorTestProbe<Int> = self.testKit.makeTestProbe()
        var behavior: Behavior<Int> = .receiveMessage { message in
            probeForTest.tell(message)
            return .same
        }

        for index in (0...100).reversed() {
            behavior = Behavior<Int>.receiveMessage { message in
                if message == index {
                    probeForTest.tell(-index)
                    return .same
                }
                return .unhandled
            }.orElse(behavior)
        }

        let ref: ActorRef<Int> = try system.spawn(.anonymous, behavior)

        ref.tell(50)
        try probeForTest.expectMessage(-50)

        probeForTest.tell(255)
        try probeForTest.expectMessage(255)
    }

    internal func testOrElseShouldProperlyApplyTerminatedToSecondBehaviorBeforeCausingDeathPactError() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let first: Behavior<Never> = .setup { context in
            let child: ActorRef<String> = try context.spawnWatch(
                "child",
                .receiveMessage { _ in
                    throw TestError("Boom")
                }
            )
            child.tell("Please throw now.")

            return .receiveSignal { _, signal in
                switch signal {
                case let terminated as Signals.Terminated:
                    probeForTest.tell("first:terminated-name:\(terminated.id.name)")

                default:
                    ()
                }
                return .unhandled
            }
        }
        let second: Behavior<Never> = .receiveSignal { _, signal in
            switch signal {
            case let terminated as Signals.Terminated:
                probeForTest.tell("second:terminated-name:\(terminated.id.name)")

            default:
                ()
            }
            return .unhandled
        }
        let ref: ActorRef<Never> = try system.spawn("orElseTerminated", first.orElse(second))
        probeForTest.watch(ref)

        try probeForTest.expectMessage("first:terminated-name:child")
        try probeForTest.expectMessage("second:terminated-name:child")
        // Neither signal handler handled Terminated, so the death pact applies.
        try probeForTest.expectTerminated(ref)
    }

    internal func testOrElseShouldCanonicalizeNestedSetupInAlternative() throws {
        let probeForTest: ActorTestProbe<OrElseMessage> = self.testKit.makeTestProbe()

        let first: Behavior<OrElseMessage> = .receiveMessage { _ in
            .unhandled
        }
        let second: Behavior<OrElseMessage> = .setup { _ in
            probeForTest.tell(.second)
            return .setup { _ in
                probeForTest.tell(.second)
                return .receiveMessage { message in
                    probeForTest.tell(message)
                    return .unhandled
                }
            }
        }
        let ref: ActorRef<OrElseMessage> = try system.spawn(.anonymous, first.orElse(second))

        ref.tell(.second)
        try probeForTest.expectMessage(.second)
        try probeForTest.expectMessage(.second)
        try probeForTest.expectMessage(.second)
        try probeForTest.expectNoMessage(for: .milliseconds(10))
    }
}
