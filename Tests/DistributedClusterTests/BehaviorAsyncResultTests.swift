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

internal final class BehaviorAsyncResultTests: SingleClusterSystemXCTestCase {
    internal func testOnResultAsyncShouldExecuteContinuationWhenFutureSucceeds() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let probe: ActorTestProbe<Int> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            context.onResultAsync(of: future, timeout: .milliseconds(300)) { result in
                switch result {
                case .success(let res):
                    probe.tell(res)

                case .failure(let error):
                    throw error
                }
                return .same
            }

            return .receiveMessage { _ in
                .same
            }
        }

        try system.spawn(.anonymous, behavior)

        promise.succeed(1)
        try probe.expectMessage(1)
    }

    internal func testOnResultAsyncShouldExecuteContinuationWhenFutureFails() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let probe: ActorTestProbe<NonTransportableAnyError> = self.testKit.makeTestProbe(
            expecting: NonTransportableAnyError.self
        )
        let error: Error = self.testKit.error()

        let behavior: Behavior<String> = .setup { context in
            context.onResultAsync(of: future, timeout: .milliseconds(300)) { result in
                switch result {
                case .success:
                    throw self.testKit.error()

                case .failure(let error):
                    probe.tell(.init(error))
                }
                return .same
            }

            return .receiveMessage { _ in
                .same
            }
        }

        try system.spawn(.anonymous, behavior)

        promise.fail(error)
        _ = try probe.expectMessage()
    }

    internal func testOnResultAsyncShouldAssignBehaviorFromContinuationWhenFutureSucceeds() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let resultProbe: ActorTestProbe<Int> = self.testKit.makeTestProbe()
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            context.onResultAsync(of: future, timeout: .milliseconds(300)) { result in
                switch result {
                case .success(let res):
                    resultProbe.tell(res)

                case .failure(let error):
                    throw error
                }
                return .receiveMessage { message in
                    probe.tell("assigned:\(message)")
                    return .same
                }
            }

            return .receiveMessage { message in
                probe.tell("started:\(message)")
                return .same
            }
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        promise.succeed(1)
        try resultProbe.expectMessage(1)

        ref.tell("test")
        try probe.expectMessage("assigned:test")
    }

    internal func testOnResultAsyncShouldCanonicalizeBehaviorFromContinuationWhenFutureSucceeds() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let resultProbe: ActorTestProbe<Int> = self.testKit.makeTestProbe()
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            context.onResultAsync(of: future, timeout: .milliseconds(300)) { result in
                switch result {
                case .success(let res):
                    resultProbe.tell(res)

                case .failure(let error):
                    throw error
                }
                return .setup { _ in
                    probe.tell("setup")
                    return .receiveMessage { _ in
                        .same
                    }
                }
            }

            return .receiveMessage { _ in
                .same
            }
        }

        try system.spawn(.anonymous, behavior)

        promise.succeed(1)
        try resultProbe.expectMessage(1)

        try probe.expectMessage("setup")
    }

    internal func testOnResultAsyncShouldKeepProcessingMessagesWhileFutureIsNotCompleted() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let resultProbe: ActorTestProbe<Int> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            context.onResultAsync(of: future, timeout: .seconds(3)) { result in
                switch result {
                case .success(let res):
                    resultProbe.tell(res)

                case .failure(let error):
                    throw error
                }
                return .same
            }

            return .receiveMessage { message in
                probe.tell("started:\(message)")
                return .same
            }
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        ref.tell("test")
        try probe.expectMessage("started:test")

        ref.tell("test2")
        try probe.expectMessage("started:test2")

        promise.succeed(1)
        try resultProbe.expectMessage(1)
    }

    internal func testOnResultAsyncShouldAllowChangingBehaviorWhileFutureIsNotCompleted() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let resultProbe: ActorTestProbe<Int> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            context.onResultAsync(of: future, timeout: .seconds(3)) { result in
                switch result {
                case .success(let res):
                    resultProbe.tell(res)

                case .failure(let error):
                    throw error
                }
                return .receiveMessage { message in
                    probe.tell("assigned:\(message)")
                    return .same
                }
            }

            return .receiveMessage { message in
                probe.tell("started:\(message)")
                return .receiveMessage { message in
                    probe.tell("changed:\(message)")
                    return .same
                }
            }
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)

        ref.tell("test")
        try probe.expectMessage("started:test")

        ref.tell("test")
        try probe.expectMessage("changed:test")

        promise.succeed(1)
        try resultProbe.expectMessage(1)

        ref.tell("test")
        try probe.expectMessage("assigned:test")
    }

    internal func testOnResultAsyncThrowingShouldExecuteContinuationWhenFutureSucceeds() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let probe: ActorTestProbe<Int> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            context.onResultAsyncThrowing(of: future, timeout: .milliseconds(300)) { value in
                probe.tell(value)
                return .same
            }

            return .receiveMessage { _ in
                .same
            }
        }

        try system.spawn(.anonymous, behavior)

        promise.succeed(1)
        try probe.expectMessage(1)
    }

    internal func testOnResultAsyncThrowingShouldFailActorWhenFutureFails() throws {
        let eventLoop: EventLoop = self.eventLoopGroup.next()
        let promise: EventLoopPromise<Int> = eventLoop.makePromise()
        let future: EventLoopFuture<Int> = promise.futureResult
        let probe: ActorTestProbe<Never> = self.testKit.makeTestProbe()
        let error: Error = self.testKit.error()

        let behavior: Behavior<String> = .setup { context in
            context.onResultAsyncThrowing(of: future, timeout: .milliseconds(300)) { _ in
                .same
            }

            return .receiveMessage { _ in
                .same
            }
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)
        probe.watch(ref)

        promise.fail(error)
        try probe.expectTerminated(ref)
    }
}
