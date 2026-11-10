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

internal final class DeathWatchTests: WatchTestCase {
    internal func testWatchShouldTriggerTerminatedWhenWatchedActorStops() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(
            "stopMePlz0", self.stopOnAnyMessage(probe: probeForTest.ref)
        )

        probeForTest.watch(stoppableRef)

        stoppableRef.tell(.stop)

        // the order of these messages is also guaranteed:
        // 1) first the dying actor has last chance to signal a message,
        try probeForTest.expectMessage("I (stopMePlz0) will now stop")
        // 2) and then terminated messages are sent:
        // try p.expectMessage("/user/terminationWatcher received .terminated for: /user/stopMePlz")
        try probeForTest.expectTerminated(stoppableRef)
    }

    internal func testWatchWithShouldTriggerCustomMessageWhenWatchedActorStops() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(
            "stopMePlz0", self.stopOnAnyMessage(probe: probeForTest.ref)
        )

        try system.spawn(
            "watcher",
            Behavior<String>.setup { context in
                context.watch(stoppableRef, with: "terminated:\(stoppableRef.id.path)")
                stoppableRef.tell(.stop)
                return
                    (Behavior<String>.receiveMessage { message in
                        probeForTest.tell(message)
                        return .same
                    }).receiveSpecificSignal(Signals.Terminated.self) { _, terminated in
                        probeForTest.tell("signal:\(terminated.id.path)")  // should not be signalled (!)
                        return .same
                    }
            }
        )

        // the order of these messages is also guaranteed:
        // 1) first the dying actor has last chance to signal a message,
        try probeForTest.expectMessage("I (stopMePlz0) will now stop")
        // 2) and then terminated messages are sent:
        try probeForTest.expectMessage("terminated:/user/stopMePlz0")
        // most notably, NOT the `signal:...` message
    }

    internal func testWatchWithCalledMultipleTimesShouldCarryTheLatestMessage() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(
            "stopMePlz0", self.stopOnAnyMessage(probe: probeForTest.ref)
        )

        try system.spawn(
            "watcher",
            Behavior<String>.setup { context in
                context.watch(stoppableRef, with: "terminated-1:\(stoppableRef.id.path)")
                context.watch(stoppableRef, with: "terminated-2:\(stoppableRef.id.path)")
                context.watch(stoppableRef, with: "terminated-3:\(stoppableRef.id.path)")
                stoppableRef.tell(.stop)
                return
                    (Behavior<String>.receiveMessage { message in
                        probeForTest.tell(message)
                        return .same
                    }).receiveSpecificSignal(Signals.Terminated.self) { _, terminated in
                        probeForTest.tell("signal:\(terminated)")  // should not be signalled (!)
                        return .same
                    }
            }
        )

        // the order of these messages is also guaranteed:
        // 1) first the dying actor has last chance to signal a message,
        try probeForTest.expectMessage("I (stopMePlz0) will now stop")
        // 2) and then terminated messages are sent:
        try probeForTest.expectMessage("terminated-3:/user/stopMePlz0")
        // most notably, NOT the `signal:...` message
    }

    internal func testWatchWithCalledMultipleTimesShouldAllowGettingBackToSignalDelivery() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(
            "stopMePlz0", self.stopOnAnyMessage(probe: probeForTest.ref)
        )

        try system.spawn(
            "watcher",
            Behavior<String>.setup { context in
                context.watch(stoppableRef, with: "terminated-1:\(stoppableRef.id.path)")
                context.watch(stoppableRef, with: "terminated-2:\(stoppableRef.id.path)")
                context.watch(stoppableRef, with: nil)
                stoppableRef.tell(.stop)
                return
                    (Behavior<String>.receiveMessage { message in
                        probeForTest.tell(message)  // should NOT be signalled, we're back to Signals
                        return .same
                    }).receiveSpecificSignal(Signals.Terminated.self) { _, terminated in
                        probeForTest.tell("signal:\(terminated.id.path)")  // should be signalled (!)
                        return .same
                    }
            }
        )

        // the order of these messages is also guaranteed:
        // 1) first the dying actor has last chance to signal a message,
        try probeForTest.expectMessage("I (stopMePlz0) will now stop")
        // 2) and then terminated messages are sent:
        try probeForTest.expectMessage("signal:/user/stopMePlz0")
        // most notably, NOT the `signal:...` message
    }

    internal func testWatchFromMultipleActorsShouldTriggerTerminatedWhenWatchedActorStops() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("p", expecting: String.self)
        let firstProbe: ActorTestProbe<String> = self.testKit.makeTestProbe("p1", expecting: String.self)
        let secondProbe: ActorTestProbe<String> = self.testKit.makeTestProbe("p2", expecting: String.self)

        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(
            "stopMePlz1", self.stopOnAnyMessage(probe: probeForTest.ref)
        )

        firstProbe.watch(stoppableRef)
        secondProbe.watch(stoppableRef)

        stoppableRef.tell(.stop)
        stoppableRef.tell(.stop)  // should result in dead letter
        stoppableRef.tell(.stop)  // should result in dead letter
        stoppableRef.tell(.stop)  // should result in dead letter

        try probeForTest.expectMessage("I (stopMePlz1) will now stop")
        // since the first message results in the actor becoming .stop
        // it should not be able to forward any new messages after the first one:
        try probeForTest.expectNoMessage(for: .milliseconds(100))

        //    try p1.expectTerminated(stoppableRef)
        //    try p2.expectTerminated(stoppableRef)
        ClusterThread.sleep(.milliseconds(1_000))
    }

    internal func testWatchFromMultipleActorsShouldNotifyOfTerminationOnlyCurrentWatchers() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("p")
        let firstProbe: ActorTestProbe<String> = self.testKit.makeTestProbe("p1")
        let secondProbe: ActorTestProbe<String> = self.testKit.makeTestProbe("p2")

        // p3 will not watch by itself, but serve as our observer for what our in-line defined watcher observes
        let unwatchedPartner: ActorTestProbe<String> = self.testKit.makeTestProbe("p3-not-really")

        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(
            "stopMePlz2", self.stopOnAnyMessage(probe: probeForTest.ref)
        )

        firstProbe.watch(stoppableRef)
        secondProbe.watch(stoppableRef)
        let notActuallyWatching: ActorRef<String> = try system.spawn(
            "notActuallyWatching",
            .setup { context in
                context.watch(stoppableRef)  // watching...
                context.unwatch(stoppableRef)  // ... not *actually* watching!
                return Behavior<String>.receiveMessage { message in
                    switch message {
                    case "ping":
                        unwatchedPartner.tell("pong")
                        return .same

                    default:
                        fatalError("no other message is expected")
                    }
                }
                .receiveSpecificSignal(Signals.Terminated.self) { _, _ in
                    unwatchedPartner.tell("whoops: actually DID receive terminated!")
                    return .same
                }
            }
        )

        // we need to perform this ping/pong dance since watch/unwatch are async, so we only know they have been sent
        // once we get a reply for a message from this actor (i.e. it has completed its setup).
        notActuallyWatching.tell("ping")
        try unwatchedPartner.expectMessage("pong")

        stoppableRef.tell(.stop)

        try probeForTest.expectMessage("I (stopMePlz2) will now stop")

        try firstProbe.expectTerminated(stoppableRef)
        try secondProbe.expectTerminated(stoppableRef)
        try unwatchedPartner.expectNoMessage(for: .milliseconds(1_000))  // make su
    }

    internal func testWatchAnAlreadyStoppedActorRefShouldReplyWithTerminated() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("alreadyDeadWatcherProbe")

        let alreadyDead: ActorRef<String> = try system.spawn("alreadyDead", .stop)

        probeForTest.watch(alreadyDead)
        try probeForTest.expectTerminated(alreadyDead)

        // even if a new actor comes in and performs the watch, it also should notice that `alreadyDead` is dead
        let secondProbe: ActorTestProbe<String> = self.testKit.makeTestProbe("alreadyDeadWatcherProbe2")
        secondProbe.watch(alreadyDead)
        try secondProbe.expectTerminated(alreadyDead)

        // `p` though should not accidentally get another .terminated when p2 installed the watch.
        try probeForTest.expectNoTerminationSignal(for: .milliseconds(200))
    }

    internal func testEnsureOnlySingleTerminatedSignalEmittedByWatchedChildDies() throws {
        let probeForTest: ActorTestProbe<Signals.Terminated> = self.testKit.makeTestProbe()
        let parentProbe: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let spawnSomeStoppers: Behavior<String> = Behavior<String>.setup { context in
            let one: ActorRef<String> = try context.spawnWatch(
                "stopper",
                .receiveMessage { _ in
                    .stop
                }
            )
            one.tell("stop")

            return .same
        }.receiveSignal { _, signal in
            switch signal {
            case let terminated as Signals.Terminated:
                probeForTest.tell(terminated)

            default:
                ()  // ok
            }
            parentProbe.tell("\(signal)")
            return .same  // ignore the child death, remain alive
        }

        let _: ActorRef<String> = try system.spawn("parent", spawnSomeStoppers)

        let terminated: Signals.Terminated = try probeForTest.expectMessage()
        let expectedPath: ActorPath = try ActorPath.userRoot.appending("parent").appending("stopper")

        terminated.id.path.shouldEqual(expectedPath)
        terminated.existenceConfirmed.shouldBeTrue()
        terminated.nodeTerminated.shouldBeFalse()
        terminated.shouldBe(Signals.ChildTerminated.self)
        try probeForTest.expectNoMessage(for: .milliseconds(200))
    }

    internal func testSendingToStoppedRefShouldNotCrash() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(
            "stopMePlz2", self.stopOnAnyMessage(probe: probeForTest.ref)
        )

        probeForTest.watch(stoppableRef)

        stoppableRef.tell(.stop)

        try probeForTest.expectTerminated(stoppableRef)

        stoppableRef.tell(.stop)
    }
}
