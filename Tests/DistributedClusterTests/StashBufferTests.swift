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

internal final class StashBufferTests: SingleClusterSystemXCTestCase {
    internal func test_stash_shouldStashMessages() throws {
        let probe: ActorTestProbe<Int> = self.testKit.makeTestProbe()

        let unstashBehavior: Behavior<Int> = .receiveMessage { message in
            probe.ref.tell(message)
            return .same
        }

        let behavior: Behavior<Int> = .setup { _ in
            let stash: StashBuffer<Int> = StashBuffer(capacity: 100)
            return .receive { context, message in
                switch message {
                case 10:
                    return try stash.unstashAll(context: context, behavior: unstashBehavior)

                default:
                    // use `try` once we have supervision and behaviors can throw
                    try stash.stash(message: message)
                    return .same
                }
            }
        }

        let stasher: ActorRef<Int> = try system.spawn(.anonymous, behavior)

        for index in 0...10 {
            stasher.tell(index)
        }

        for index in 0...9 {
            try probe.expectMessage(index)
        }

        stasher.tell(10)
        try probe.expectMessage(10)
    }

    internal func test_fullStash_shouldThrowWhenAttemptToStashSomeMore() throws {
        let stash: StashBuffer<Int> = StashBuffer(capacity: 1)

        try stash.stash(message: 1)

        try shouldThrow(expected: StashError.self) {
            _ = try stash.stash(message: 2)
        }
    }

    internal func test_unstash_intoSetupBehavior_shouldCanonicalize() throws {
        let probeForTest: ActorTestProbe<Int> = self.testKit.makeTestProbe(expecting: Int.self)

        _ = try self.system.spawn(
            "unstashIntoSetup",

            Behavior<Int>.setup { context in
                let stash: StashBuffer<Int> = StashBuffer<Int>(capacity: 2)
                try stash.stash(message: 1)

                return try stash.unstashAll(
                    context: context,

                    behavior: .setup { _ in
                        .receiveMessage { message in
                            probeForTest.tell(message)
                            return .stop
                        }
                    }
                )
            }
        )

        try probeForTest.expectMessage(1)
    }

    internal func test_messagesStashedAgainDuringUnstashingShouldNotBeProcessedInTheSameRun() throws {
        let probe: ActorTestProbe<Int> = self.testKit.makeTestProbe()

        let stash: StashBuffer<Int> = StashBuffer(capacity: 100)

        let unstashBehavior: Behavior<Int> = .receiveMessage { message in
            try stash.stash(message: message)
            probe.ref.tell(message)
            return .same
        }

        let behavior: Behavior<Int> = .receive { context, message in
            switch message {
            case 10:
                return try stash.unstashAll(context: context, behavior: unstashBehavior)

            default:
                // use `try` once we have supervision and behaviors can throw
                try stash.stash(message: message)
                return .same
            }
        }

        let stasher: ActorRef<Int> = try system.spawn(.anonymous, behavior)

        for index in 0...10 {
            stasher.tell(index)
        }

        // we are expecting to get each stashed message once
        for index in 0...9 {
            try probe.expectMessage(index)
        }

        // No we send another message, that should be send back to us.
        // If the stash would unstash the messages that have been stashed
        // during the same unstash run, we should get 0 instead of 10 and the
        // test would fail.
        stasher.tell(10)
        try probe.expectMessage(10)
    }
}
