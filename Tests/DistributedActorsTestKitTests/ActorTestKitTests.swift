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

import XCTest

@testable import DistributedActorsTestKit
@testable import DistributedCluster

internal final class ActorTestKitTests: XCTestCase {
    private var system: ClusterSystem?
    private var testKit: ActorTestKit?

    override internal func setUp() async {
        let actorSystem: ClusterSystem = await ClusterSystem(String(describing: type(of: self)))
        self.system = actorSystem
        self.testKit = ActorTestKit(actorSystem)
    }

    override internal func tearDown() async throws {
        let actorSystem: ClusterSystem = try XCTUnwrap(self.system)
        try await actorSystem.shutdown().wait()
    }

    internal func test_error_withMessage() throws {
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        let error: Error = kit.error("test")
        "\(error)".contains("test").shouldBeTrue()
    }

    internal func test_fail_shouldNotImmediatelyFailWithinEventuallyBlock() throws {
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        var counter: Int = 0

        try kit.eventually(within: .seconds(1), interval: .milliseconds(10)) {
            if counter < 5 {
                counter += 1
                throw kit.fail("This should not fail the test")
            }
        }
    }

    internal func test_nestedEventually_shouldProperlyHandleFailures() throws {
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        var outerCounter: Int = 0
        var innerCounter: Int = 0

        try kit.eventually(within: .seconds(1), interval: .milliseconds(11)) {
            try kit.eventually(within: .milliseconds(100)) {
                if innerCounter < 5 {
                    innerCounter += 1
                    throw kit.error("This should not fail the test")
                }
            }

            if outerCounter < 5 {
                outerCounter += 1
                throw kit.fail("This should not fail the test")
            }
        }
    }

    internal func test_fishForMessages() throws {
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        let probe: ActorTestProbe<String> = kit.makeTestProbe(expecting: String.self)

        probe.tell("yes-1")
        probe.tell("yes-2")
        probe.tell("no-1")
        probe.tell("no-2")
        probe.tell("yes-3")
        probe.tell("yes-end")

        let messages: [String] = try probe.fishForMessages(within: .seconds(30)) { message in
            if message.contains("yes-end") {
                return .catchComplete
            }
            if message.contains("yes") {
                return .catchContinue
            }
            return .ignore
        }

        messages.shouldEqual(
            [
                "yes-1",
                "yes-2",
                "yes-3",
                "yes-end",
            ]
        )
    }

    internal func test_fishForTransformed() throws {
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        let probe: ActorTestProbe<String> = kit.makeTestProbe(expecting: String.self)

        probe.tell("yes-1")
        probe.tell("yes-2")
        probe.tell("no-1")
        probe.tell("no-2")
        probe.tell("yes-3")
        probe.tell("yes-end")

        let messages: [String] = try probe.fishFor(String.self, within: .seconds(30)) { message in
            if message.contains("yes-end") {
                return .catchComplete("\(message)!!!")
            }
            if message.contains("yes") {
                return .catchContinue("\(message)!!!")
            }
            return .ignore
        }

        messages.shouldEqual(
            [
                "yes-1!!!",
                "yes-2!!!",
                "yes-3!!!",
                "yes-end!!!",
            ]
        )
    }

    internal func test_fishFor_canThrow() throws {
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        let probe: ActorTestProbe<String> = kit.makeTestProbe(expecting: String.self)

        probe.tell("yes-1")

        do {
            _ = try probe.fishForMessages(within: .seconds(30)) { message in
                throw TestError("Boom: \(message)")
            }
            throw kit.fail("Should have thrown")
        } catch {
            "\(error)".shouldContain("Boom: yes-1")
        }
    }
}
