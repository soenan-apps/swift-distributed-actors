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

internal final class BehaviorAwaitThrowingTests: SingleClusterSystemXCTestCase {
    private func awaitResultThrowingBehavior(
        future: EventLoopFuture<Int>,
        timeout: Duration,
        probe: ActorTestProbe<String>,
        suspendProbe: ActorTestProbe<Int>
    ) -> Behavior<String> {
        .receive { context, message in
            switch message {
            case "suspend":
                return context.awaitResultThrowing(of: future, timeout: timeout) { value in
                    suspendProbe.tell(value)
                    return .same
                }

            default:
                probe.tell(message)
                return .same
            }
        }
    }

    internal func testAwaitResultThrowingShouldResumeActorSuccessResultWhenFutureSucceeds() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let suspendProbe: ActorTestProbe<Int> = self.testKit.makeTestProbe()
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = self.awaitResultThrowingBehavior(
            future: future,
            timeout: .seconds(1),
            probe: probeForTest,
            suspendProbe: suspendProbe
        )

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        ref.tell("test")
        try probeForTest.expectMessage("test")

        ref.tell("suspend")
        try probeForTest.expectNoMessage(for: .milliseconds(10))
        try suspendProbe.expectNoMessage(for: .milliseconds(10))

        ref.tell("another test")
        try probeForTest.expectNoMessage(for: .milliseconds(10))
        try suspendProbe.expectNoMessage(for: .milliseconds(10))

        promise.succeed(1)
        try suspendProbe.expectMessage(1)
        try probeForTest.expectMessage("another test")
    }

    internal func testAwaitResultThrowingShouldCrashActorWhenFutureFails() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let suspendProbe: ActorTestProbe<Int> = self.testKit.makeTestProbe()
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = self.awaitResultThrowingBehavior(
            future: future,
            timeout: .seconds(1),
            probe: probeForTest,
            suspendProbe: suspendProbe
        )

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)
        probeForTest.watch(ref)

        ref.tell("test")
        try probeForTest.expectMessage("test")

        ref.tell("suspend")
        try probeForTest.expectNoMessage(for: .milliseconds(10))
        try suspendProbe.expectNoMessage(for: .milliseconds(10))

        ref.tell("another test")
        try probeForTest.expectNoMessage(for: .milliseconds(10))
        try suspendProbe.expectNoMessage(for: .milliseconds(10))

        promise.fail(self.testKit.error())
        try suspendProbe.expectNoMessage(for: .milliseconds(10))
        try probeForTest.expectTerminated(ref)
    }

    internal func testAwaitResultThrowingShouldCrashActorWhenFutureTimesOut() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let suspendProbe: ActorTestProbe<Int> = self.testKit.makeTestProbe()
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = self.awaitResultThrowingBehavior(
            future: future,
            timeout: .milliseconds(10),
            probe: probeForTest,
            suspendProbe: suspendProbe
        )

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)
        probeForTest.watch(ref)

        ref.tell("test")
        try probeForTest.expectMessage("test")

        ref.tell("suspend")
        try probeForTest.expectNoMessage(for: .milliseconds(10))
        try suspendProbe.expectNoMessage(for: .milliseconds(10))

        ref.tell("another test")
        try probeForTest.expectNoMessage(for: .milliseconds(10))
        try suspendProbe.expectNoMessage(for: .milliseconds(10))

        try probeForTest.expectTerminated(ref)
    }
}
