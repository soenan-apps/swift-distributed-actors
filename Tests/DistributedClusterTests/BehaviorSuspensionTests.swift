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

internal final class BehaviorSuspensionTests: SingleClusterSystemXCTestCase {
    internal struct Boom: Error {
        internal let message: String

        internal init(_ message: String) {
            self.message = message
        }
    }

    internal func testSuspendedActorShouldBeUnsuspendedOnResumeSystemMessage() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .intercept(
            behavior: .receiveMessage { _ in
                .suspend { (msg: Result<Int, Error>) in
                    probeForTest.tell("unsuspended:\(msg)")
                    return .receiveMessage { msg in
                        probeForTest.tell("resumed:\(msg)")
                        return .same
                    }
                }
            },
            with: ProbeInterceptor(probe: probeForTest)
        )

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        ref.tell("something")  // this message causes the actor the suspend

        try probeForTest.expectMessage("something")

        ref.tell("something else")  // actor is suspended and should not process this message

        try probeForTest.expectNoMessage(for: .milliseconds(50))

        ref.sendSystemMessage(.resume(.success(1)))

        try probeForTest.expectMessage("unsuspended:success(1)")
        try probeForTest.expectMessage("resumed:something else")
    }

    internal func testSuspendedActorShouldStaySuspendedWhenResumeHandlerSuspendsAgain() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .intercept(
            behavior: .receiveMessage { _ in
                .suspend { (msg: Result<Int, Error>) in
                    probeForTest.tell("suspended:\(msg)")
                    return .suspend { (msg: Result<String, Error>) in
                        probeForTest.tell("unsuspended:\(msg)")
                        return .receiveMessage { msg in
                            probeForTest.tell("resumed:\(msg)")
                            return .same
                        }
                    }
                }
            },
            with: ProbeInterceptor(probe: probeForTest)
        )

        let ref: ActorRef<String> = try system.spawn("suspender", behavior)

        ref.tell("something")  // this message causes the actor the suspend

        try probeForTest.expectMessage("something")

        ref.tell("something else")  // actor is suspended and should not process this message
        try probeForTest.expectNoMessage(for: .milliseconds(50))

        ref.sendSystemMessage(.resume(.success(1)))  // actor will process the resume handler, but stay suspended
        try probeForTest.expectMessage("suspended:success(1)")
        try probeForTest.expectNoMessage(for: .milliseconds(50))

        ref.tell("last")  // actor is still suspended and should not process this message
        try probeForTest.expectNoMessage(for: .milliseconds(50))

        ref.sendSystemMessage(.resume(.success("test")))

        try probeForTest.expectMessage("unsuspended:success(\"test\")")
        try probeForTest.expectMessage("resumed:something else")
        try probeForTest.expectMessage("resumed:last")
    }

    internal func testSuspendedActorShouldBeUnsuspendedOnFailedResumeSystemMessage() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .intercept(
            behavior: .receiveMessage { _ in
                .suspend { (msg: Result<Int, Error>) in
                    switch msg {
                    case .success(let res):
                        probeForTest.tell("unsuspended:\(res)")

                    case .failure(let error):
                        probeForTest.tell("unsuspended:\(error)")
                    }
                    return .receiveMessage { msg in
                        probeForTest.tell("resumed:\(msg)")
                        return .same
                    }
                }
            },
            with: ProbeInterceptor(probe: probeForTest)
        )

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        ref.tell("something")  // this message causes the actor the suspend

        try probeForTest.expectMessage("something")

        ref.tell("something else")  // actor is suspended and should not process this message

        try probeForTest.expectNoMessage(for: .milliseconds(50))

        ref.sendSystemMessage(.resume(.failure(Boom(""))))

        try probeForTest.expectMessage().shouldStartWith(prefix: "unsuspended:Boom")
        try probeForTest.expectMessage("resumed:something else")
    }

    internal func testSuspendedActorShouldKeepProcessingSystemMessages() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .receiveMessage { _ in
            .suspend { (msg: Result<Int, Error>) in
                switch msg {
                case .success(let res):
                    probeForTest.tell("unsuspended:\(res)")

                case .failure(let error):
                    probeForTest.tell("unsuspended:\(error)")
                }
                return .receiveMessage { msg in
                    probeForTest.tell("resumed:\(msg)")
                    return .same
                }
            }
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)
        probeForTest.watch(ref)

        ref.tell("something")  // this message causes the actor the suspend

        ref.sendSystemMessage(.stop)

        try probeForTest.expectTerminated(ref)
    }

    internal func testSuspendedActorShouldKeepProcessingSignals() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = Behavior<String>.receive { context, _ in
            probeForTest.tell("suspended")
            try context.spawnWatch("child", Behavior<String>.stop)
            return .suspend { (msg: Result<Int, Error>) in
                switch msg {
                case .success(let res):
                    probeForTest.tell("unsuspended:\(res)")

                case .failure(let error):
                    probeForTest.tell("unsuspended:\(error)")
                }
                return .same
            }
        }.receiveSignal { _, signal in
            guard let string = signal as? Signals.Terminated else {
                return .same
            }
            probeForTest.tell("signal:\(string.id.name)")

            // returning this behavior should not unsuspend the actor
            return Behavior<String>.receiveMessage { msg in
                probeForTest.tell("changedBySignal:\(msg)")
                return .same
            }
        }

        let ref: ActorRef<String> = try system.spawn("parent", behavior)

        ref.tell("something")  // this message causes the actor to suspend
        try probeForTest.expectMessage("suspended")

        // This message remains suspended even though the signal changes the behavior.
        ref.tell("something else")

        try probeForTest.expectMessage("signal:child")

        ref.sendSystemMessage(.resume(.success(1)))

        try probeForTest.expectMessage("unsuspended:1")
        try probeForTest.expectMessage("changedBySignal:something else")
    }

    internal func testSuspendedActorShouldStopWhenSignalHandlerReturnsStopped() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = Behavior<String>.receive { context, _ in
            probeForTest.tell("suspended")
            try context.spawnWatch("child", Behavior<String>.stop)
            return .suspend { (msg: Result<Int, Error>) in
                switch msg {
                case .success(let res):
                    probeForTest.tell("unsuspended:\(res)")

                case .failure(let error):
                    probeForTest.tell("unsuspended:\(error)")
                }
                return .same
            }
        }.receiveSignal { _, _ in
            .stop
        }

        let ref: ActorRef<String> = try system.spawn("parent", behavior)
        probeForTest.watch(ref)

        ref.tell("something")  // this message causes the actor the suspend
        try probeForTest.expectMessage("suspended")

        try probeForTest.expectTerminated(ref)
    }
}
