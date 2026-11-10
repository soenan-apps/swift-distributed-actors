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

internal final class SupervisionAsyncTests: SupervisionTestCase {
    internal func assertDispatchedFailureRestart(failBy failureMode: FailureMode) throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { _ in
            probeForTest.tell("setup")
            return .receive { context, msg in
                let callback: AsynchronousCallback<String> = context.makeAsynchronousCallback { str in
                    probeForTest.tell("crashing:\(str)")
                    try failureMode.fail()
                }

                let shell: ActorShell<String> = try XCTUnwrap(context as? ActorShell<String>)
                shell.messageDispatcher.execute {
                    callback.invoke(msg)
                }

                return .same
            }
        }

        let ref: ActorRef<String> = try system.spawn(
            .anonymous,
            behavior,
            props: .supervision(strategy: .restart(atMost: 5, within: .seconds(5)))
        )
        probeForTest.watch(ref)

        try probeForTest.expectMessage("setup")

        ref.tell("test")
        try probeForTest.expectMessage("crashing:test")
        try probeForTest.expectNoTerminationSignal(for: .milliseconds(50))

        try probeForTest.expectMessage("setup")
        ref.tell("test2")
        try probeForTest.expectMessage("crashing:test2")
    }

    internal func testSupervisorThrowsShouldRestartWhenFailingInDispatchedClosure() throws {
        try self.assertDispatchedFailureRestart(failBy: .throwing)
    }

    internal func assertAwaitedFailureRestart(failBy failureMode: FailureMode) throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let elg: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop: EventLoop = elg.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise(of: Int.self)
        let future: EventLoopFuture<Int> = promise.futureResult

        let behavior: Behavior<String> = .setup { context in
            probeForTest.tell("starting")
            return .receiveMessage { message in
                switch message {
                case "suspend":
                    return context.awaitResult(of: future, timeout: .milliseconds(100)) { _ in
                        try failureMode.fail()
                        return .same
                    }

                default:
                    probeForTest.tell(message)
                    return .same
                }
            }
        }

        let ref: ActorRef<String> = try system.spawn(
            .anonymous,
            behavior,
            props: Props.supervision(strategy: .restart(atMost: 1, within: .seconds(1)))
        )

        try probeForTest.expectMessage("starting")
        ref.tell("suspend")
        promise.succeed(1)
        try probeForTest.expectMessage("starting")
    }

    internal func testSupervisorAwaitResultShouldInvokeSupervisionOnThrow() throws {
        try self.assertAwaitedFailureRestart(failBy: .throwing)
    }

    internal func testSupervisorAwaitResultThrowingShouldInvokeSupervisionOnFailure() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let elg: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop: EventLoop = elg.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise(of: Int.self)
        let future: EventLoopFuture<Int> = promise.futureResult

        let behavior: Behavior<String> = .setup { context in
            probeForTest.tell("starting")
            return .receiveMessage { message in
                switch message {
                case "suspend":
                    return context.awaitResultThrowing(of: future, timeout: .milliseconds(100)) { _ in
                        .same
                    }

                default:
                    probeForTest.tell(message)
                    return .same
                }
            }
        }

        let ref: ActorRef<String> = try system.spawn(
            .anonymous,
            behavior,
            props: Props.supervision(strategy: .restart(atMost: 1, within: .seconds(1)))
        )

        try probeForTest.expectMessage("starting")
        ref.tell("suspend")
        promise.fail(FaultyError.boom(message: "boom"))
        try probeForTest.expectMessage("starting")
    }
}
