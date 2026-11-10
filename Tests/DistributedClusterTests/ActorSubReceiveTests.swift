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

internal final class ActorSubReceiveTests: SingleClusterSystemXCTestCase {
    internal struct TestSubReceiveType<Value>: Codable {}
    internal func test_subReceive_notCrashWhenTypeIncludesSpecialChar() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let refProbe: ActorTestProbe<ActorRef<TestSubReceiveType<Void>>> = self.testKit.makeTestProbe(
            expecting: ActorRef<TestSubReceiveType<Void>>.self
        )

        let behavior: Behavior<Int> = .setup { context in
            let subRef: ActorRef<TestSubReceiveType<Void>> = context.subReceive(
                "test-sub",
                TestSubReceiveType<Void>.self
            ) { message in
                probe.tell("subreceive:\(message)")
            }
            _ = context.subReceive("test-sub", TestSubReceiveType<String?>.self) { message in
                probe.tell("subreceive:\(message)")
            }
            refProbe.tell(subRef)

            return .receiveMessage { _ in .same }
        }

        try system.spawn("test-parent", behavior)

        let subRef: ActorRef<TestSubReceiveType<Void>> = try refProbe.expectMessage()

        subRef.tell(TestSubReceiveType<Void>())
        try probe.expectMessage("subreceive:\(TestSubReceiveType<Void>())")
    }

    internal func test_subReceive_shouldBeAbleToReceiveMessages() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let refProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(expecting: ActorRef<String>.self)

        let behavior: Behavior<Int> = .setup { context in
            let subRef: ActorRef<String> = context.subReceive("test-sub", String.self) { message in
                probe.tell("subreceive:\(message)")
            }
            refProbe.tell(subRef)

            return .receiveMessage { _ in .same }
        }

        try system.spawn("test-parent", behavior)

        let subRef: ActorRef<String> = try refProbe.expectMessage()

        subRef.tell("test")
        try probe.expectMessage("subreceive:test")
    }

    internal func test_subReceiveId_fromGenericType_shouldNotBlowUp() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let refProbe: ActorTestProbe<ActorRef<Set<String>>> = self.testKit.makeTestProbe(
            expecting: ActorRef<Set<String>>.self
        )

        let behavior: Behavior<Int> = .setup { context in
            let subRef: ActorRef<Set<String>> = context.subReceive(Set<String>.self) { message in
                probe.tell("subreceive:\(message.count)")
            }
            refProbe.tell(subRef)

            return .receiveMessage { _ in .same }
        }

        try system.spawn("test-parent", behavior)

        let subRef: ActorRef<Set<String>> = try refProbe.expectMessage()

        subRef.tell(Set(["one", "two"]))
        try probe.expectMessage("subreceive:2")
    }

    internal func test_subReceive_shouldBeAbleToModifyActorState() throws {
        let probe: ActorTestProbe<Int> = self.testKit.makeTestProbe(expecting: Int.self)
        let refProbe: ActorTestProbe<ActorRef<IncrementAndGet>> = self.testKit.makeTestProbe(
            expecting: ActorRef<IncrementAndGet>.self
        )

        struct GetState: Codable {
            let replyTo: ActorRef<Int>
        }

        struct IncrementAndGet: Codable {
            let replyTo: ActorRef<Int>
        }

        let behavior: Behavior<GetState> = .setup { context in
            var state: Int = 0

            let subRef: ActorRef<IncrementAndGet> = context.subReceive("test-sub", IncrementAndGet.self) { message in
                state += 1
                message.replyTo.tell(state)
            }
            refProbe.tell(subRef)

            return .receiveMessage { message in
                message.replyTo.tell(state)
                return .same
            }
        }

        let ref: ActorRef<GetState> = try system.spawn("test-parent", behavior)

        let subRef: ActorRef<IncrementAndGet> = try refProbe.expectMessage()

        var previousState: Int = 0
        for _ in 1...10 {
            subRef.tell(IncrementAndGet(replyTo: probe.ref))
            let state: Int = try probe.expectMessage()
            state.shouldEqual(previousState + 1)

            ref.tell(GetState(replyTo: probe.ref))
            try probe.expectMessage().shouldEqual(state)

            previousState = state
        }
    }

    internal func test_subReceive_shouldBeWatchable() throws {
        let probe: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)
        let refProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(expecting: ActorRef<String>.self)

        let behavior: Behavior<Never> = .setup { context in
            let subRef: ActorRef<String> = context.subReceive("test-sub", String.self) { _ in
                throw Boom("")
            }
            refProbe.tell(subRef)

            return .unhandled
        }

        try system.spawn("test-parent", behavior)

        let subRef: ActorRef<String> = try refProbe.expectMessage()

        probe.watch(subRef)

        subRef.tell("test")
        try probe.expectTerminated(subRef)
    }

    internal func test_subReceive_shouldShareLifetimeWithParent() throws {
        let probe: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)
        let refProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(expecting: ActorRef<String>.self)

        let behavior: Behavior<String> = .setup { context in
            let subRef: ActorRef<String> = context.subReceive("test-sub", String.self) { _ in
                // ignore
            }
            refProbe.tell(subRef)

            return .receiveMessage { _ in
                .stop
            }
        }

        let ref: ActorRef<String> = try system.spawn("test-parent", behavior)

        let subRef: ActorRef<String> = try refProbe.expectMessage()

        probe.watch(ref)
        probe.watch(subRef)

        ref.tell("test")

        try probe.expectTerminatedInAnyOrder([ref.asAddressable, subRef.asAddressable])
    }

    internal func shared_subReceive_shouldTriggerSupervisionOnFailure(
        failureMode: SupervisionTestCase.FailureMode
    ) throws {
        let refProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(expecting: ActorRef<String>.self)

        let behavior: Behavior<String> = .setup { context in
            let subRef: ActorRef<String> = context.subReceive("test-sub", String.self) { _ in
                try failureMode.fail()
            }
            refProbe.tell(subRef)

            return .unhandled
        }

        try system.spawn("test", behavior, props: .supervision(strategy: .restart(atMost: 5, within: .seconds(5))))

        let subRef: ActorRef<String> = try refProbe.expectMessage()

        subRef.tell("test")

        _ = try refProbe.expectMessage()  // this means the actor was restarted
    }

    internal func test_subReceive_shouldTriggerSupervisionOnError() throws {
        try self.shared_subReceive_shouldTriggerSupervisionOnFailure(failureMode: .throwing)
    }

    internal func test_subReceive_shouldBeReplacedIfRegisteredAgainUnderSameKey() throws {
        struct TestMessage: Codable {
            let replyTo: ActorRef<String>
            let message: String
        }

        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let refProbe: ActorTestProbe<ActorRef<TestMessage>> = self.testKit.makeTestProbe(
            expecting: ActorRef<TestMessage>.self
        )

        let behavior: Behavior<String> = .setup { context in
            var subReceiveCounter: Int = 0
            return .receiveMessage { message in
                if message == "install" {
                    let count: Int = subReceiveCounter
                    subReceiveCounter += 1
                    let subRef: ActorRef<TestMessage> = context.subReceive("test-sub", TestMessage.self) { message in
                        message.replyTo.tell("subReceive-\(count):\(message.message)")
                    }
                    refProbe.tell(subRef)
                }

                return .same
            }
        }

        let ref: ActorRef<String> = try system.spawn("test", behavior)

        ref.tell("install")
        let subRef: ActorRef<TestMessage> = try refProbe.expectMessage()

        subRef.tell(TestMessage(replyTo: probe.ref, message: "test"))
        try probe.expectMessage("subReceive-0:test")

        ref.tell("install")
        let subRef2: ActorRef<TestMessage> = try refProbe.expectMessage()

        subRef.tell(TestMessage(replyTo: probe.ref, message: "test"))
        try probe.expectMessage(
            "subReceive-1:test"
        )  // subReceive has been replaced, so we should get an incremented count

        subRef2.tell(TestMessage(replyTo: probe.ref, message: "test"))
        try probe.expectMessage("subReceive-1:test")  // second sub ref should also work
    }
}
