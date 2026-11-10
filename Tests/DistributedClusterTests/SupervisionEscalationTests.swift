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

internal final class SupervisionEscalationTests: SupervisionTestCase {
    internal func testEscalateSupervisedThrowsShouldKeepEscalatingThroughWatchingParents() throws {
        let terminationProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pt",
            expecting: ActorRef<String>.self
        )
        let messageProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pm",
            expecting: ActorRef<String>.self
        )
        let pab: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pab",
            expecting: ActorRef<String>.self
        )
        let bufferProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pb",
            expecting: ActorRef<String>.self
        )
        let parentProbeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("pp", expecting: String.self)

        try spawnEscalatingTree(
            topProbe: terminationProbe,
            parentProbe: parentProbeForTest,
            middle: watchingMiddleBehavior(messageProbe: messageProbe, almostBottomProbe: pab, bottomProbe: bufferProbe)
        )

        let top: ActorRef<String> = try terminationProbe.expectMessage()
        terminationProbe.watch(top)
        let middle: ActorRef<String> = try messageProbe.expectMessage()
        messageProbe.watch(middle)
        let almostBottom: ActorRef<String> = try pab.expectMessage()
        pab.watch(almostBottom)
        let bottom: ActorRef<String> = try bufferProbe.expectMessage()
        bufferProbe.watch(bottom)

        bottom.tell("Boom!")

        let message: String = try parentProbeForTest.expectMessage()
        message.shouldContain("Prevented escalation to top level in /user/top")

        // Death Parade:
        try bufferProbe.expectTerminated(bottom)  // Boom!
        try pab.expectTerminated(almostBottom)  // Boom!
        try messageProbe.expectTerminated(middle)  // Boom!

        // top should not terminate since it handled the thing
        try terminationProbe.expectNoTerminationSignal(for: .milliseconds(200))
    }

    internal func testEscalateSupervisedThrowsShouldKeepEscalatingThroughNonWatchingParents() throws {
        let terminationProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pt",
            expecting: ActorRef<String>.self
        )
        let messageProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pm",
            expecting: ActorRef<String>.self
        )
        let pab: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pab",
            expecting: ActorRef<String>.self
        )
        let bufferProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pb",
            expecting: ActorRef<String>.self
        )
        let parentProbeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("pp", expecting: String.self)

        try spawnEscalatingTree(
            topProbe: terminationProbe,
            parentProbe: parentProbeForTest,
            middle: escalatingMiddleBehavior(
                messageProbe: messageProbe,
                almostBottomProbe: pab,
                bottomProbe: bufferProbe
            )
        )

        let top: ActorRef<String> = try terminationProbe.expectMessage()
        terminationProbe.watch(top)
        let middle: ActorRef<String> = try messageProbe.expectMessage()
        messageProbe.watch(middle)
        let almostBottom: ActorRef<String> = try pab.expectMessage()
        pab.watch(almostBottom)
        let bottom: ActorRef<String> = try bufferProbe.expectMessage()
        bufferProbe.watch(bottom)

        bottom.tell("Boom!")

        let message: String = try parentProbeForTest.expectMessage()
        message.shouldContain("Prevented escalation to top level in /user/top")

        // Death Parade:
        try bufferProbe.expectTerminated(bottom)  // Boom!
        try pab.expectTerminated(almostBottom)  // Boom!
        try messageProbe.expectTerminated(middle)  // Boom!

        // top should not terminate since it handled the thing
        try terminationProbe.expectNoTerminationSignal(for: .milliseconds(200))
    }

    internal func testEscalateSupervisedThrowsShouldKeepEscalatingUntilNonEscalatingParent() throws {
        let terminationProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pt",
            expecting: ActorRef<String>.self
        )
        let messageProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pm",
            expecting: ActorRef<String>.self
        )
        let pab: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pab",
            expecting: ActorRef<String>.self
        )
        let bufferProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            "pb",
            expecting: ActorRef<String>.self
        )

        try spawnIsolatedTree(
            topProbe: terminationProbe,
            middle: isolatingMiddleBehavior(
                messageProbe: messageProbe,
                almostBottomProbe: pab,
                bottomProbe: bufferProbe
            )
        )

        let top: ActorRef<String> = try terminationProbe.expectMessage()
        terminationProbe.watch(top)
        let middle: ActorRef<String> = try messageProbe.expectMessage()
        messageProbe.watch(middle)
        let almostBottom: ActorRef<String> = try pab.expectMessage()
        pab.watch(almostBottom)
        let bottom: ActorRef<String> = try bufferProbe.expectMessage()
        bufferProbe.watch(bottom)

        bottom.tell("Boom!")

        // Death Parade:
        try bufferProbe.expectTerminated(bottom)  // Boom!
        try pab.expectTerminated(almostBottom)  // Boom!
        // Boom!

        // the almost bottom has isolated the fault; it does not leak more upwards the tree
        try messageProbe.expectNoTerminationSignal(for: .milliseconds(100))
        try terminationProbe.expectNoTerminationSignal(for: .milliseconds(100))
    }

    private func spawnEscalatingTree(
        topProbe: ActorTestProbe<ActorRef<String>>,
        parentProbe: ActorTestProbe<String>,
        middle: Behavior<String>
    ) throws {
        try system.spawn(
            "top",
            Behavior<String>.setup { context in
                topProbe.tell(context.myself)
                try context.spawn("middle", middle, props: .supervision(strategy: .escalate))
                return .receiveSpecificSignal(Signals.ChildTerminated.self) { context, terminated in
                    parentProbe.tell(
                        "Prevented escalation to top level in \(context.myself.path), terminated: \(terminated)"
                    )
                    return .same
                }
            }
        )
    }

    private func spawnIsolatedTree(topProbe: ActorTestProbe<ActorRef<String>>, middle: Behavior<String>) throws {
        try system.spawn(
            "top",
            Behavior<String>.setup { context in
                topProbe.tell(context.myself)
                try context.spawn("middle", middle)
                return .ignore
            }
        )
    }

    private func watchingMiddleBehavior(
        messageProbe: ActorTestProbe<ActorRef<String>>,
        almostBottomProbe: ActorTestProbe<ActorRef<String>>,
        bottomProbe: ActorTestProbe<ActorRef<String>>
    ) -> Behavior<String> {
        .setup { context in
            messageProbe.tell(context.myself)
            try context.spawnWatch(
                "almostBottom",
                self.watchingBottomBehavior(almostBottomProbe: almostBottomProbe, bottomProbe: bottomProbe)
            )
            return .ignore
        }
    }

    private func escalatingMiddleBehavior(
        messageProbe: ActorTestProbe<ActorRef<String>>,
        almostBottomProbe: ActorTestProbe<ActorRef<String>>,
        bottomProbe: ActorTestProbe<ActorRef<String>>
    ) -> Behavior<String> {
        .setup { context in
            messageProbe.tell(context.myself)
            try context.spawn(
                "almostBottom",
                self.nonWatchingBottomBehavior(almostBottomProbe: almostBottomProbe, bottomProbe: bottomProbe),
                props: .supervision(strategy: .escalate)
            )
            return .ignore
        }
    }

    private func isolatingMiddleBehavior(
        messageProbe: ActorTestProbe<ActorRef<String>>,
        almostBottomProbe: ActorTestProbe<ActorRef<String>>,
        bottomProbe: ActorTestProbe<ActorRef<String>>
    ) -> Behavior<String> {
        .setup { context in
            messageProbe.tell(context.myself)
            try context.spawn(
                "almostBottom",
                self.nonWatchingBottomBehavior(almostBottomProbe: almostBottomProbe, bottomProbe: bottomProbe)
            )
            return .ignore
        }
    }

    private func watchingBottomBehavior(
        almostBottomProbe: ActorTestProbe<ActorRef<String>>,
        bottomProbe: ActorTestProbe<ActorRef<String>>
    ) -> Behavior<String> {
        .setup { context in
            almostBottomProbe.tell(context.myself)
            try context.spawnWatch(
                "bottom",
                self.failingBottomBehavior(probe: bottomProbe),
                props: .supervision(strategy: .escalate)
            )
            return .ignore
        }
    }

    private func nonWatchingBottomBehavior(
        almostBottomProbe: ActorTestProbe<ActorRef<String>>,
        bottomProbe: ActorTestProbe<ActorRef<String>>
    ) -> Behavior<String> {
        .setup { context in
            almostBottomProbe.tell(context.myself)
            try context.spawn(
                "bottom",
                self.failingBottomBehavior(probe: bottomProbe),
                props: .supervision(strategy: .escalate)
            )
            return .ignore
        }
    }

    private func failingBottomBehavior(probe: ActorTestProbe<ActorRef<String>>) -> Behavior<String> {
        .setup { context in
            probe.tell(context.myself)
            return .receiveMessage { message in
                throw Boom(message)
            }
        }
    }
}
