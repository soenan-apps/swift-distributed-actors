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

import DistributedCluster
import XCTest

@testable import DistributedActorsTestKit

internal final class ActorTestProbeTests: SingleClusterSystemXCTestCase {
    internal func test_maybeExpectMessage_shouldReturnTheReceivedMessage() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe("p2", expecting: String.self)

        probe.tell("one")

        try probe.maybeExpectMessage().shouldEqual("one")
    }

    internal func test_maybeExpectMessage_shouldReturnNilIfTimeoutExceeded() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe("p2", expecting: String.self)

        probe.tell("one")

        try probe.maybeExpectMessage().shouldEqual("one")
    }

    internal func test_expectNoMessage() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe("p3", expecting: String.self)

        try probeForTest.expectNoMessage(for: .milliseconds(100))
        probeForTest.stop()
    }

    internal func test_shouldBeWatchable() throws {
        let watchedProbe: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)
        let watchingProbe: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)

        watchingProbe.watch(watchedProbe.ref)

        watchedProbe.stop()

        try watchingProbe.expectTerminated(watchedProbe.ref)
    }

    internal func test_expectMessageAnyOrderSuccess() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let messages: [String] = ["test1", "test2", "test3", "test4"]

        for message in messages.reversed() {
            probeForTest.ref.tell(message)
        }

        try probeForTest.expectMessagesInAnyOrder(messages)
    }
}
