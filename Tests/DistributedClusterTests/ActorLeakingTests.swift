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

import Atomics
import DistributedActorsConcurrencyHelpers
import DistributedActorsTestKit
import Foundation
import XCTest

@testable import DistributedCluster

internal final class ActorLeakingTests: SingleClusterSystemXCTestCase {
    internal final class LeakTestMessage {
        internal let deallocated: UnsafeAtomic<Bool>?

        internal init(_ deallocated: UnsafeAtomic<Bool>?) {
            self.deallocated = deallocated
        }

        deinit {
            deallocated?.store(true, ordering: .relaxed)
        }
    }

    internal struct NotEnoughActorsAlive: Error {
        internal let expected: Int
        internal let current: Int
    }

    internal struct TooManyActorsAlive: Error {
        internal let expected: Int
        internal let current: Int
    }

    internal func test_spawn_stop_shouldNotLeakActors() throws {
        #if !SACT_TESTS_LEAKS
        return self.skipLeakTests()
        #else
        let stopsOnAnyMessage: Behavior<String> = .receiveMessage { _ in
            .stop
        }

        var ref: ActorRef<String>? = try system.spawn("printer", stopsOnAnyMessage)

        let afterStartActorCount: Int = try testKit.eventually(within: .milliseconds(200)) { () -> Int in
            let counter: Int = self.system.userCellInitCounter.load(ordering: .relaxed)
            if counter != 1 {
                throw NotEnoughActorsAlive(expected: 1, current: counter)
            }
            return counter
        }

        ref?.tell("please stop")
        ref = nil

        let afterStopActorCount: Int = try testKit.eventually(within: .milliseconds(200)) { () -> Int in
            let counter: Int = self.system.userCellInitCounter.load(ordering: .relaxed)
            if counter != 0 {
                throw TooManyActorsAlive(expected: 0, current: counter)
            }
            return counter
        }

        afterStartActorCount.shouldEqual(1)
        afterStopActorCount.shouldEqual(0)
        #endif
    }

    internal func test_spawn_stop_shouldNotLeakActorThatCloseOverContext() throws {
        #if !SACT_TESTS_LEAKS
        return self.skipLeakTests()
        #else
        let stopsOnAnyMessage: Behavior<String> = .setup { context in
            .receiveMessage { _ in
                context.log.debug("just so we actually close over context ;)")
                return .stop
            }
        }

        var ref: ActorRef<String>? = try system.spawn("printer", stopsOnAnyMessage)

        let afterStartActorCount: Int = try testKit.eventually(within: .milliseconds(200)) { () -> Int in
            let counter: Int = self.system.userCellInitCounter.load(ordering: .relaxed)
            if counter != 1 {
                throw NotEnoughActorsAlive(expected: 1, current: counter)
            }
            return counter
        }

        ref?.tell("please stop")
        ref = nil

        let afterStopActorCount: Int = try testKit.eventually(within: .milliseconds(200)) { () -> Int in
            let counter: Int = self.system.userCellInitCounter.load(ordering: .relaxed)
            if counter != 0 {
                throw TooManyActorsAlive(expected: 0, current: counter)
            }
            return counter
        }

        afterStartActorCount.shouldEqual(1)
        afterStopActorCount.shouldEqual(0)
        #endif
    }

    internal func test_spawn_stop_shouldNotLeakMailbox() throws {
        #if !SACT_TESTS_LEAKS
        return self.skipLeakTests()
        #else
        let stopsOnAnyMessage: Behavior<String> = .receiveMessage { _ in
            .stop
        }

        var ref: ActorRef<String>? = try system.spawn("stopsOnAnyMessage", stopsOnAnyMessage)

        let afterStartMailboxCount: Int = try testKit.eventually(within: .milliseconds(200)) { () -> Int in
            let counter: Int = self.system.userMailboxInitCounter.load(ordering: .relaxed)
            if counter != 1 {
                throw NotEnoughActorsAlive(expected: 1, current: counter)
            }
            return counter
        }

        ref?.tell("please stop")
        ref = nil

        let afterStopMailboxCount: Int = try testKit.eventually(within: .milliseconds(200)) { () -> Int in
            let counter: Int = self.system.userMailboxInitCounter.load(ordering: .relaxed)
            if counter != 0 {
                throw TooManyActorsAlive(expected: 0, current: counter)
            }
            return counter
        }

        afterStartMailboxCount.shouldEqual(1)
        afterStopMailboxCount.shouldEqual(0)

        #endif
    }

    internal func test_parentWithChildrenStopping_shouldNotLeakActors() throws {
        #if !SACT_TESTS_LEAKS
        return self.skipLeakTests()
        #else
        let spawnsNChildren: Behavior<Int> = .receive { context, childCount in
            if childCount == 0 {
                return .stop
            }
            for _ in 1...childCount {
                let secondValue: Behavior<String> = .receiveMessage { _ in .same }
                try context.spawn(.anonymous, secondValue)
            }
            return .same
        }

        var ref: ActorRef<Int>? = try system.spawn("printer", spawnsNChildren)

        let expectedParentCount: Int = 1
        let expectedChildrenCount: Int = 3
        let expectedActorCount: Int = expectedParentCount + expectedChildrenCount

        ref?.tell(expectedChildrenCount)

        let afterStartActorCount: Int = try testKit.eventually(within: .milliseconds(200)) { () -> Int in
            let counter: Int = self.system.userCellInitCounter.load(ordering: .relaxed)
            if counter != expectedActorCount {
                throw NotEnoughActorsAlive(expected: expectedActorCount, current: counter)
            }
            return counter
        }

        ref?.tell(0)  // stops the parent actor
        ref = nil

        let afterStopActorCount: Int = try testKit.eventually(within: .milliseconds(200)) { () -> Int in
            let counter: Int = self.system.userCellInitCounter.load(ordering: .relaxed)
            if counter != 0 {
                throw TooManyActorsAlive(expected: 0, current: counter)
            }
            return counter
        }

        afterStartActorCount.shouldEqual(expectedActorCount)
        afterStopActorCount.shouldEqual(0)
        #endif
    }

    internal func skipLeakTests(function: String = #function) {
        pnote(
            "Skipping leak test \(function), it will only be executed if -DSACT_TESTS_LEAKS is enabled.",
            file: #fileID,
            line: #line
        )
    }
}
