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

import Distributed
import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster
@testable import Logging

private distributed actor Greeter {
    typealias ActorSystem = ClusterSystem

    distributed func greet(name: String) -> String {
        "hello \(name)!"
    }
}
internal final class DeadLetterTests: SingleClusterSystemXCTestCase {
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: DeadLetterOffice tests

    internal func test_deadLetters_logWithSourcePosition() throws {
        let log: Logger = self.logCapture.logger(label: "/dead/letters")

        let id: ActorID = try ActorID(
            local: self.system.cluster.node,
            path: ActorPath.userRoot.appending(
                "someone"
            ),
            incarnation: .random()
        )
        let office: DeadLetterOffice = DeadLetterOffice(log, id: id, system: system)

        office.deliver("Hello")

        try self.logCapture.awaitLogContaining(self.testKit, text: "was not delivered to [/user/someone")
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: ClusterSystem integrated tests

    internal func test_sendingToTerminatedActor_shouldResultInDeadLetter() throws {
        let ref: ActorRef<String> = try self.system.spawn(
            "ludwig",

            .receiveMessage { _ in
                .stop
            }
        )
        let probe: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)

        probe.watch(ref)
        ref.tell("terminate please")
        try probe.expectTerminated(ref)

        ref.tell("Are you still there?")

        try self.logCapture.awaitLogContaining(self.testKit, text: "Are you still there?")
        try self.logCapture.awaitLogContaining(self.testKit, text: "/user/ludwig")
    }

    internal func test_askingTerminatedActor_shouldResultInDeadLetter() async throws {
        let ref: ActorRef<String> = try self.system.spawn(
            "ludwig",

            .receiveMessage { _ in
                .stop
            }
        )
        let probe: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)

        probe.watch(ref)
        ref.tell("terminate please")
        try probe.expectTerminated(ref)

        sleep(1)

        let answer: AskResponse<String> = ref.ask(timeout: .milliseconds(100)) { replyTo in
            "This is a question, reply to \(replyTo)"
        }

        _ = try await shouldThrow {
            try await answer.value
        }

        try self.logCapture.awaitLogContaining(self.testKit, text: "This is a question")
        try self.logCapture.awaitLogContaining(self.testKit, text: "/user/ludwig")
    }

    internal func test_remoteCallTerminatedTarget_shouldResultInDeadLetter() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.enabled = true
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.enabled = true
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        var greeter: Greeter? = Greeter(actorSystem: local)
        let greeterID: ActorID = try XCTUnwrap(greeter).id
        let remoteGreeterRef: Greeter = try Greeter.resolve(id: greeterID, using: remote)

        let testKit: ActorTestKit = self.testKit(local)
        let probe: ActorTestProbe<String> = testKit.makeTestProbe(expecting: String.self)
        try await probe.watch(XCTUnwrap(greeter))

        greeter = nil
        try await probe.expectTermination(of: greeterID)

        let error: Error = try await shouldThrow {
            _ = try await remoteGreeterRef.greet(name: "world")
        }

        guard error is DeadLetterError else {
            throw testKit.fail("Expected DeadLetterError, got \(error)")
        }

        try self.capturedLogs(of: local).awaitLogContaining(self.testKit, text: "was not delivered to")
    }

    internal func test_resolveTerminatedTarget_shouldResultInDeadLetter() async throws {
        var greeter: Greeter? = Greeter(actorSystem: self.system)
        let greeterID: ActorID = try XCTUnwrap(greeter).id

        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        try await probe.watch(XCTUnwrap(greeter))

        greeter = nil
        try await probe.expectTermination(of: greeterID)

        let error: Error = try shouldThrow {
            _ = try self.system.resolve(id: greeterID, as: Greeter.self)
        }

        guard error is DeadLetterError else {
            throw self.testKit.fail("Expected DeadLetterError, got \(error)")
        }
    }
}
