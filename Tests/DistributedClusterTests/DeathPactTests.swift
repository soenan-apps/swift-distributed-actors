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

internal final class DeathPactTests: WatchTestCase {
    internal func testMinimizedDeathPactShouldTriggerForWatchedActor() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe("pp", expecting: String.self)

        let juliet: ActorRef<String> = try system.spawn(
            "juliet",
            Behavior<String>.receiveMessage { _ in
                .same
            }
        )

        let romeo: ActorRef<String> = try system.spawn(
            "romeo",
            Behavior<String>.setup { context in
                context.watch(juliet)

                return .receiveMessage { msg in
                    probe.ref.tell("reply:\(msg)")
                    return .same
                }
            }
        )

        probe.watch(juliet)
        probe.watch(romeo)

        romeo.tell("hi")
        try probe.expectMessage("reply:hi")

        // internal hacks
        let fakeTerminated: SystemMessages = .terminated(ref: juliet.asAddressable, existenceConfirmed: true)
        romeo.sendSystemMessage(fakeTerminated)

        try probe.expectTerminated(romeo)
    }

    internal func testDeathPactIgnoresTerminationAfterUnwatch() throws {
        // Tests a very specific situation where romeo watches juliet, juliet terminates and sends .terminated
        // yet during that time, romeo unwatches her. This means that the .terminated message could arrive at
        // romeo AFTER the unwatch has been triggered. In this situation we DO NOT want to trigger the death pact,
        // since romeo by that time "does not care" about juliet anymore and should not die because of the .terminated.
        //
        // The .terminated message should also NOT be delivered to the .receiveSignal handler, it should
        // be as if the watcher
        // never watched juliet to begin with. (This also is important so Swift Distributed Actors
        // semantics are the same as what users would manually be able to to)

        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe("pp", expecting: String.self)

        let juliet: ActorRef<String> = try system.spawn(
            "juliet",
            Behavior<String>.receiveMessage { _ in
                .same
            }
        )

        let romeo: ActorRef<String> = try system.spawn(
            "romeo",
            Behavior<String>.receive { context, message in
                switch message {
                case "watch":
                    context.watch(juliet)
                    probe.tell("reply:watch")

                case "unwatch":
                    context.unwatch(juliet)
                    probe.tell("reply:unwatch")

                default:
                    fatalError("should not happen")
                }
                return .same
            }.receiveSignal { _, signal in
                if case let terminated as Signals.Terminated = signal {
                    probe.tell("Unexpected terminated received!!! \(terminated)")
                }
                return .same
            }
        )

        probe.watch(juliet)
        probe.watch(romeo)

        romeo.tell("watch")
        try probe.expectMessage("reply:watch")
        romeo.tell("unwatch")
        try probe.expectMessage("reply:unwatch")

        // internal hacks; we simulate that Juliet has terminated, and enqueued the .terminated before
        // the unwatch managed to reach her
        let fakeTerminated: SystemMessages = .terminated(ref: juliet.asAddressable, existenceConfirmed: true)
        romeo.sendSystemMessage(fakeTerminated)

        // should NOT trigger the receiveSignal handler (which notifies the probe)
        try probe.expectNoMessage(for: .milliseconds(100))
    }

    internal func testDeathPactShouldMakeWatcherKillItselfWhenWatcheeStops() throws {
        let romeo: ActorRef<RomeoMessage> = try system.spawn(
            "romeo",
            Behavior<RomeoMessage>.receive { context, message in
                switch message {
                case let .pleaseWatch(juliet, probe):
                    context.watch(juliet)
                    probe.tell(.done)
                    return .same
                }
            }  // NOT handling signal on purpose, we are in a Death Pact
        )

        let juliet: ActorRef<JulietMessage> = try system.spawn(
            "juliet",
            Behavior<JulietMessage>.receiveMessage { message in
                switch message {
                case .takePoison:
                    return .stop  // "stop myself"
                }
            }
        )

        let probeForTest: ActorTestProbe<Done> = self.testKit.makeTestProbe("p", expecting: Done.self)

        probeForTest.watch(juliet)
        probeForTest.watch(romeo)

        romeo.tell(.pleaseWatch(juliet: juliet, probe: probeForTest.ref))
        try probeForTest.expectMessage(.done)

        juliet.tell(.takePoison)

        try probeForTest.expectTerminatedInAnyOrder([juliet.asAddressable, romeo.asAddressable])
    }

    internal func testDeathPactShouldMakeWatcherKillItselfWhenWatcheeThrows() throws {
        let romeo: ActorRef<RomeoMessage> = try system.spawn(
            "romeo",
            Behavior<RomeoMessage>.receive { context, message in
                switch message {
                case let .pleaseWatch(juliet, probe):
                    context.watch(juliet)
                    probe.tell(.done)
                    return .same
                }
            }  // NOT handling signal on purpose, we are in a Death Pact
        )

        let juliet: ActorRef<JulietMessage> = try system.spawn(
            "juliet",
            Behavior<JulietMessage>.receiveMessage { message in
                switch message {
                case .takePoison:
                    throw TakePoisonError()  // "stop myself"
                }
            }
        )

        let probeForTest: ActorTestProbe<Done> = self.testKit.makeTestProbe("p", expecting: Done.self)

        probeForTest.watch(juliet)
        probeForTest.watch(romeo)

        romeo.tell(.pleaseWatch(juliet: juliet, probe: probeForTest.ref))
        try probeForTest.expectMessage(.done)

        juliet.tell(.takePoison)

        try probeForTest.expectTerminatedInAnyOrder([juliet.asAddressable, romeo.asAddressable])
    }
}
