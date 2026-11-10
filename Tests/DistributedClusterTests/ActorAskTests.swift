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

internal final class ActorAskTests: SingleClusterSystemXCTestCase {
    internal struct AnswerMePlease: Codable {
        internal let replyTo: ActorRef<String>
    }

    internal struct TestMessage: Codable {
        internal let replyTo: ActorRef<String>
    }

    internal func test_ask_forSimpleType() async throws {
        let behavior: Behavior<TestMessage> = .receiveMessage { closureArgument in
            closureArgument.replyTo.tell("received")
            return .stop
        }

        let ref: ActorRef<TestMessage> = try system.spawn(.anonymous, behavior)

        let response: AskResponse<String> = ref.ask(timeout: .seconds(1)) { TestMessage(replyTo: $0) }

        let result: String = try await response.value

        result.shouldEqual("received")
    }

    internal func test_ask_shouldSucceedIfResponseIsReceivedBeforeTimeout() async throws {
        let behavior: Behavior<TestMessage> = .receiveMessage { closureArgument in
            closureArgument.replyTo.tell("received")
            return .stop
        }

        let ref: ActorRef<TestMessage> = try system.spawn(.anonymous, behavior)

        let response: AskResponse<String> = ref.ask(timeout: .seconds(1)) { TestMessage(replyTo: $0) }

        let result: String = try await response.value

        result.shouldEqual("received")
    }

    internal func test_ask_shouldFailIfResponseIsNotReceivedBeforeTimeout() async throws {
        let behavior: Behavior<TestMessage> = .receiveMessage { _ in
            .stop
        }

        let ref: ActorRef<TestMessage> = try system.spawn(.anonymous, behavior)

        let response: AskResponse<String> = ref.ask(timeout: .seconds(1)) { TestMessage(replyTo: $0) }

        let error: Error = try await shouldThrow {
            _ = try await response.value
        }

        guard let remoteCallError = error as? RemoteCallError, case .timedOut = remoteCallError.underlying.error else {
            throw testKit.fail("Expected RemoteCallError.timedOut, got \(error)")
        }
    }

    internal func test_ask_shouldCompleteWithFirstResponse() async throws {
        let behavior: Behavior<TestMessage> = .receiveMessage { closureArgument in
            closureArgument.replyTo.tell("received:1")
            closureArgument.replyTo.tell("received:2")
            return .stop
        }

        let ref: ActorRef<TestMessage> = try system.spawn(.anonymous, behavior)

        let response: AskResponse<String> = ref.ask(timeout: .milliseconds(1)) { replyTo in
            TestMessage(replyTo: replyTo)
        }

        let result: String = try await response.value

        result.shouldEqual("received:1")
    }

    internal func test_askResult_shouldBePossibleTo_contextAwaitOn() throws {
        let probe: ActorTestProbe<String> = testKit.makeTestProbe(expecting: String.self)

        let greeter: ActorRef<AnswerMePlease> = try system.spawn(
            "greeterAskReply",

            .receiveMessage { message in
                message.replyTo.tell("Hello there")
                return .stop
            }
        )

        let _: ActorRef<Never> = try system.spawn(
            "awaitOnAskResult",

            .setup { context in
                let askResult: AskResponse<String> = greeter.ask(timeout: .seconds(1)) { replyTo in
                    AnswerMePlease(replyTo: replyTo)
                }

                return context.awaitResultThrowing(of: askResult, timeout: .seconds(1)) { greeting in
                    probe.tell(greeting)
                    return .stop
                }
            }
        )

        try probe.expectMessage("Hello there")
    }

    internal func shared_askResult_shouldBePossibleTo_contextOnResultAsyncOn(withTimeout timeout: Duration) throws {
        let probe: ActorTestProbe<String> = testKit.makeTestProbe(expecting: String.self)

        let greeter: ActorRef<AnswerMePlease> = try system.spawn(
            "greeterAskReply",

            .receiveMessage { message in
                message.replyTo.tell("Hello there")
                return .stop
            }
        )

        let _: ActorRef<Int> = try system.spawn(
            "askingAndOnResultAsyncThrowing",

            .setup { context in
                let askResult: AskResponse<String> = greeter.ask(timeout: timeout) { replyTo in
                    AnswerMePlease(replyTo: replyTo)
                }

                context.onResultAsyncThrowing(of: askResult, timeout: timeout) { greeting in
                    probe.tell(greeting)
                    return .same
                }

                // cannot become .ignore since that results in "become .same in .setup"
                // See also issue #746
                return .receiveMessage { _ in .same }
            }
        )

        try probe.expectMessage("Hello there", within: .seconds(3))
    }

    internal func test_askResult_shouldBePossibleTo_contextOnResultAsyncOn_withNormalTimeout() throws {
        try self.shared_askResult_shouldBePossibleTo_contextOnResultAsyncOn(withTimeout: .seconds(1))
    }

    internal func test_askResult_shouldBePossibleTo_contextOnResultAsyncOn_withInfiniteTimeout() throws {
        try self.shared_askResult_shouldBePossibleTo_contextOnResultAsyncOn(withTimeout: .effectivelyInfinite)
    }

    internal func test_askResult_whenContextAwaitedOn_shouldRespectTimeout() throws {
        let probe: ActorTestProbe<String> = testKit.makeTestProbe(expecting: String.self)

        let void: ActorRef<AnswerMePlease> = try system.spawn("theVoid", (.receiveMessage { _ in .same }))

        let _: ActorRef<Never> = try system.spawn(
            "onResultAsync",

            .setup { context in
                let askResult: AskResponse<String> = void.ask(timeout: .seconds(1)) { replyTo in
                    AnswerMePlease(replyTo: replyTo)
                }

                return context.awaitResult(of: askResult, timeout: .milliseconds(100)) { greeting in
                    switch greeting {
                    case .failure(let err):
                        probe.tell("\(err)")

                    case .success:
                        probe.tell("no timeout...")
                    }
                    return .stop
                }
            }
        )

        let message: String = try probe.expectMessage()
        message.shouldStartWith(prefix: "RemoteCallError(timedOut(")
        message.shouldContain(
            """
                DistributedCluster.TimeoutError(message: \"AskResponse<String> timed out after 100ms\", timeout: \
                0.1 seconds))
                """
        )
    }

    internal func test_ask_onDeadLetters_shouldPutMessageIntoDeadLetters() async throws {
        let ref: ActorRef<AnswerMePlease> = system.deadLetters.adapt(from: AnswerMePlease.self)

        let result: AskResponse<String> = ref.ask(timeout: .milliseconds(300)) { closureArgument in
            AnswerMePlease(replyTo: closureArgument)
        }

        let error: Error = try await shouldThrow {
            try await result.value
        }

        guard let remoteCallError = error as? RemoteCallError, case .timedOut = remoteCallError.underlying.error else {
            throw testKit.fail("Expected RemoteCallError.timedOut, got \(error)")
        }
    }

    internal func test_ask_withTerminatedSystem_shouldNotCauseCrash() async throws {
        let system: ClusterSystem = await self.setUpNode("AskCrashSystem")

        let ref: ActorRef<TestMessage> = try system.spawn(
            .unique("responder"),
            .receiveMessage { message in
                    message.replyTo.tell("test")
                    return .same
            }
        )

        try await system.shutdown().wait()

        let _: AskResponse<String> = ref.ask(timeout: .milliseconds(300)) { replyTo in
            TestMessage(replyTo: replyTo)
        }
    }
}
