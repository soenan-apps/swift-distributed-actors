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

internal final class BehaviorAwaitResultTests: SingleClusterSystemXCTestCase {
    private func awaitResultBehavior(
        future: EventLoopFuture<Int>,
        timeout: Duration,
        probe: ActorTestProbe<String>? = nil,
        suspendProbe: ActorTestProbe<Result<Int, ErrorEnvelope>>? = nil
    ) -> Behavior<String> {
        .receive { context, message in
            switch message {
            case "suspend":
                return context.awaitResult(of: future, timeout: timeout) { result in
                    suspendProbe?.tell(result.mapError { error in ErrorEnvelope(error) })
                    return .same
                }

            default:
                probe?.tell(message)
                return .same
            }
        }
    }

    internal func testAwaitResultShouldResumeActorWithSuccessResultWhenFutureSucceeds() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let suspendProbe: ActorTestProbe<Result<Int, ErrorEnvelope>> = self.testKit.makeTestProbe()
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = self.awaitResultBehavior(
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
        let suspendResult: Result<Int, ErrorEnvelope> = try suspendProbe.expectMessage()
        switch suspendResult {
        case .success(1):
            ()

        default:
            XCTFail("Expected success(1), got \(suspendResult)")
        }

        try probeForTest.expectMessage("another test")
    }

    internal func testAwaitResultShouldResumeActorWithFailureResultWhenFutureFails() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let suspendProbe: ActorTestProbe<Result<Int, ErrorEnvelope>> = self.testKit.makeTestProbe()
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = self.awaitResultBehavior(
            future: future,
            timeout: .seconds(1),
            probe: probeForTest,
            suspendProbe: suspendProbe
        )

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        ref.tell("suspend")
        ref.tell("another test")
        try probeForTest.expectNoMessage(for: .milliseconds(10))
        try suspendProbe.expectNoMessage(for: .milliseconds(10))

        promise.fail(self.testKit.error())
        let suspendResult: Result<Int, ErrorEnvelope> = try suspendProbe.expectMessage()
        switch suspendResult {
        case .failure(let errorEnvelope):
            guard let error = errorEnvelope.error as? BestEffortStringError,
                error.representation.contains("\(String(reflecting: CallSiteError.self))")
            else {
                throw probeForTest.error(
                    "Expected failure(ExecutionException(underlying: CallSiteError())), got \(suspendResult)"
                )
            }

        default:

            throw probeForTest.error(

                "Expected failure(ExecutionException(underlying: CallSiteError())), got \(suspendResult)"

            )
        }

        try probeForTest.expectMessage("another test")
    }

    internal func testAwaitResultShouldResumeActorWithFailureResultWhenFutureTimesOut() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let suspendProbe: ActorTestProbe<Result<Int, ErrorEnvelope>> = self.testKit.makeTestProbe()
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = self.awaitResultBehavior(
            future: future,
            timeout: .milliseconds(10),
            probe: probeForTest,
            suspendProbe: suspendProbe
        )

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        ref.tell("suspend")

        let suspendResult: Result<Int, ErrorEnvelope> = try suspendProbe.expectMessage()
        switch suspendResult {
        case .failure(let errorEnvelope):
            guard let error = errorEnvelope.error as? BestEffortStringError,
                error.representation.contains("\(String(reflecting: TimeoutError.self))")
            else {
                throw probeForTest.error(
                    "Expected failure(ExecutionException(underlying: TimeoutError)), got \(suspendResult)"
                )
            }

        default:

            throw probeForTest.error(

                "Expected failure(ExecutionException(underlying: TimeoutError)), got \(suspendResult)"

            )
        }

        ref.tell("test")
        try probeForTest.expectMessage("test")
    }

    internal func testAwaitResultShouldWorkWhenReturnedInsideInitialSetup() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let suspendProbe: ActorTestProbe<Result<Int, ErrorEnvelope>> = self.testKit.makeTestProbe()
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            probeForTest.tell("initializing")
            return context.awaitResult(of: future, timeout: .milliseconds(100)) { result in
                suspendProbe.tell(result.mapError { error in ErrorEnvelope(error) })
                return .receiveMessage { message in
                    probeForTest.tell(message)
                    return .same
                }
            }
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        try probeForTest.expectMessage("initializing")
        ref.tell("while-suspended")  // hits the actor while it's still suspended

        let suspendResult: Result<Int, ErrorEnvelope> = try suspendProbe.expectMessage()
        switch suspendResult {
        case .failure(let errorEnvelope):
            guard let error = errorEnvelope.error as? BestEffortStringError,
                error.representation.contains("\(String(reflecting: TimeoutError.self))")
            else {
                throw probeForTest.error(
                    "Expected failure(ExecutionException(underlying: TimeoutError)), got \(suspendResult)"
                )
            }

        default:
            throw probeForTest.error(
                "Expected failure(ExecutionException(underlying: TimeoutError)), got \(suspendResult)"
            )
        }

        try probeForTest.expectMessage("while-suspended")

        ref.tell("test")
        try probeForTest.expectMessage("test")
    }

    internal func testAwaitResultShouldCrashWhenReturnedInsideInitialSetupAndReturnSameOnResume() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let suspendProbe: ActorTestProbe<Result<Int, ErrorEnvelope>> = self.testKit.makeTestProbe()
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            probeForTest.tell("initializing")
            return context.awaitResult(of: future, timeout: .milliseconds(10)) { result in
                suspendProbe.tell(result.mapError { error in ErrorEnvelope(error) })
                return .same
            }
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)
        probeForTest.watch(ref)

        try probeForTest.expectMessage("initializing")

        let suspendResult: Result<Int, ErrorEnvelope> = try suspendProbe.expectMessage()
        switch suspendResult {
        case .failure(let errorEnvelope):
            guard let error = errorEnvelope.error as? BestEffortStringError,
                error.representation.contains("\(String(reflecting: TimeoutError.self))")
            else {
                throw probeForTest.error(
                    "Expected failure(ExecutionException(underlying: TimeoutError)), got \(suspendResult)"
                )
            }

        default:
            throw probeForTest.error(
                "Expected failure(ExecutionException(underlying: TimeoutError)), got \(suspendResult)"
            )
        }

        try probeForTest.expectTerminated(ref)
    }

    internal func testAwaitResultAllowBecomingIntoSetup() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let suspendProbe: ActorTestProbe<Result<Int, ErrorEnvelope>> = self.testKit.makeTestProbe()
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            probeForTest.tell("initializing")
            return .receiveMessage { _ in
                context.awaitResult(of: future, timeout: .seconds(3)) { result in
                    .setup { _ in
                        suspendProbe.tell(result.mapError { error in ErrorEnvelope(error) })
                        return .same
                    }
                }
            }
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)
        probeForTest.watch(ref)
        try probeForTest.expectMessage("initializing")

        ref.tell("wake up")
        promise.succeed(13)

        let suspendResult: Result<Int, ErrorEnvelope> = try suspendProbe.expectMessage()
        switch suspendResult {
        case .success(let value):
            value.shouldEqual(13)

        default:
            throw probeForTest.error("Expected success, got \(suspendResult)")
        }
    }
}
