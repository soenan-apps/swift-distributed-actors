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
import XCTest

@testable import DistributedCluster

internal final class BehaviorCanonicalizeTests: SingleClusterSystemXCTestCase {
    internal func test_canonicalize_nestedSetupBehaviors() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("canonicalizeProbe1")

        let secondValue: Behavior<String> = .setup { _ in
            probeForTest.tell("outer-1")
            return .setup { _ in
                probeForTest.tell("inner-2")
                return .setup { _ in
                    probeForTest.tell("inner-3")
                    return .receiveMessage { messageForTest in
                        probeForTest.tell("received:\(messageForTest)")
                        return .same
                    }
                }
            }
        }

        let ref: ActorRef<String> = try system.spawn("nestedSetups", secondValue)

        try probeForTest.expectMessage("outer-1")
        try probeForTest.expectMessage("inner-2")
        try probeForTest.expectMessage("inner-3")
        try probeForTest.expectNoMessage(for: .milliseconds(100))
        ref.tell("ping")
        try probeForTest.expectMessage("received:ping")
    }

    internal func test_canonicalize_doesSurviveDeeplyNestedSetups() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("canonicalizeProbe2")

        func deepSetupRabbitHole(currentDepth depth: Int, stopAt limit: Int) -> Behavior<String> {
            .setup { _ in
                if depth < limit {
                    // add another "setup layer"
                    return deepSetupRabbitHole(currentDepth: depth + 1, stopAt: limit)
                }
                return .receiveMessage { msg in
                    probeForTest.tell("received:\(msg)")
                    return .stop
                }
            }
        }

        // we attempt to cause a stack overflow by nesting tons of setups inside each other.
        // this could fail if canonicalization were implemented in some naive way.
        let depthLimit: Int =
            self.system.settings.actor.maxBehaviorNestingDepth - 2  // not a good idea, but we should not crash
        let ref: ActorRef<String> = try system.spawn(
            "deepSetupNestedRabbitHole",
            deepSetupRabbitHole(
                currentDepth: 0,
                stopAt: depthLimit
            )
        )

        ref.tell("ping")
        try probeForTest.expectMessage("received:ping")
    }

    internal func test_canonicalize_unwrapInterceptBehaviors() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("canonicalizeProbe3")

        let secondValue: Behavior<String> = .intercept(
            behavior: .setup { _ in
                probeForTest.tell("outer-1")
                return .setup { _ in
                    probeForTest.tell("inner-2")
                    return .receiveMessage { messageForTest in
                        probeForTest.tell("received:\(messageForTest)")
                        return .same
                    }
                }
            },
            with: ProbeInterceptor(probe: probeForTest)
        )

        let ref: ActorRef<String> = try system.spawn("nestedSetups", secondValue)

        try probeForTest.expectMessage("outer-1")
        try probeForTest.expectMessage("inner-2")
        try probeForTest.expectNoMessage(for: .milliseconds(100))
        ref.tell("ping")
        try probeForTest.expectMessage("ping")
        try probeForTest.expectMessage("received:ping")
    }

    internal func test_canonicalize_orElse_shouldThrowOnTooDeeplyNestedBehaviors() throws {
        let probeForTest: ActorTestProbe<Int> = self.testKit.makeTestProbe()
        var behavior: Behavior<Int> = .receiveMessage { message in
            probeForTest.tell(message)
            return .same
        }

        for index in (0...self.system.settings.actor.maxBehaviorNestingDepth).reversed() {
            behavior = Behavior<Int>.receiveMessage { message in
                if message == index {
                    probeForTest.tell(-index)
                    return .same
                }
                return .unhandled
            }.orElse(behavior)
        }

        let ref: ActorRef<Int> = try system.spawn(.anonymous, behavior)
        probeForTest.watch(ref)
        try probeForTest.expectTerminated(ref)
    }

    internal func test_canonicalize_orElse_executeNestedSetupOnBecome() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let ref: ActorRef<String> = try system.spawn(
            "orElseCanonicalizeNestedSetups",

            .receiveMessage { _ in
                let onlyA: Behavior<String> = Behavior<String>.setup { _ in
                    probeForTest.ref.tell("setup:onlyA")
                    return .receiveMessage { msg in
                        switch msg {
                        case "A":
                            probeForTest.ref.tell("got:A")
                            return .same

                        default:
                            return .unhandled
                        }
                    }
                }
                let onlyB: Behavior<String> = Behavior<String>.setup { _ in
                    probeForTest.ref.tell("setup:onlyB")
                    return .receiveMessage { msg in
                        switch msg {
                        case "B":
                            probeForTest.ref.tell("got:B")
                            return .same

                        default:
                            return .unhandled
                        }
                    }
                }
                return onlyA.orElse(onlyB)
            }
        )

        ref.tell("run the setups")

        try probeForTest.expectMessage("setup:onlyA")
        try probeForTest.expectMessage("setup:onlyB")
        ref.tell("A")
        try probeForTest.expectMessage("got:A")
        ref.tell("B")
        try probeForTest.expectMessage("got:B")
    }

    internal func test_startBehavior_shouldThrowOnTooDeeplyNestedBehaviorSetups() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("startBehaviorProbe")

        // Creates an infinitely nested setup behavior -- it is used to see that we detect this and abort executing
        // eagerly
        func setupDaDoRunRunRunDaDoRunRun(depth: Int = 0) -> Behavior<String> {
            .setup { _ in
                probeForTest.tell("at:\(depth)")
                return setupDaDoRunRunRunDaDoRunRun(depth: depth + 1)
            }
        }

        // if issue #244 is implemented, we cna supervise and "spy on" start() failures making this test much more
        // specific

        let behavior: Behavior<String> = setupDaDoRunRunRunDaDoRunRun()
        try system.spawn("nestedSetups", behavior)

        for depth in 0..<self.system.settings.actor.maxBehaviorNestingDepth {
            try probeForTest.expectMessage("at:\(depth)")
        }
        try probeForTest.expectNoMessage(for: .milliseconds(50))
    }

    internal func test_stopWithoutPostStop_shouldUsePreviousBehavior() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = Behavior.receiveMessage { _ in
            .stop
        }.receiveSignal { _, signal in
            if signal is Signals.PostStop {
                probeForTest.tell("postStop")
            }
            return .same
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)
        probeForTest.watch(ref)

        ref.tell("test")

        try probeForTest.expectMessage("postStop")
        try probeForTest.expectTerminated(ref)
    }

    internal func test_stopWithPostStop_shouldUseItForPostStopSignalHandling() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = Behavior.receiveMessage { _ in
            .stop { _ in
                probeForTest.tell("postStop")
            }
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)
        probeForTest.watch(ref)

        ref.tell("test")

        try probeForTest.expectMessage("postStop")
        try probeForTest.expectTerminated(ref)
    }

    internal func test_setup_returningSameShouldThrow() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { _ in
            .same
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        probeForTest.watch(ref)

        try probeForTest.expectTerminated(ref)
    }
}
