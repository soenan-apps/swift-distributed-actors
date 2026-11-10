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

internal final class SupervisionSetupTests: SupervisionTestCase {
    internal func assertSetupFailureRestart(failureMode: FailureMode) throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)

        let strategy: SupervisionStrategy = .restart(atMost: 5, within: .seconds(10))
        var shouldFail: Bool = true
        let behavior: Behavior<String> = .setup { _ in
            if shouldFail {
                shouldFail = false  // we only fail the first time
                probe.tell("failing")
                try failureMode.fail()
            }

            probe.tell("starting")

            return .receiveMessage { message in
                probe.tell("started:\(message)")
                return .same
            }
        }

        let ref: ActorRef<String> = try system.spawn(
            "fail-in-start-1",
            behavior,
            props: .supervision(strategy: strategy)
        )

        try probe.expectMessage("failing")
        try probe.expectMessage("starting")
        ref.tell("test")
        try probe.expectMessage("started:test")
    }

    internal func assertSetupFailureAfterRestart(failureMode: FailureMode) throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)

        let strategy: SupervisionStrategy = .restart(atMost: 5, within: .seconds(10))
        // initial setup should not fail
        var shouldFail: Bool = false
        let behavior: Behavior<String> = .setup { _ in
            if shouldFail {
                shouldFail = false
                probe.tell("setup:failing")
                try failureMode.fail()
            }

            shouldFail = true  // next setup should fail

            probe.tell("starting")

            return .receiveMessage { message in
                switch message {
                case "boom":
                    throw FaultyError.boom(
                        message:
                            "boom"
                    )

                default:
                    probe.tell("started:\(message)")
                    return .same
                }
            }
        }

        let ref: ActorRef<String> = try system.spawn(
            "fail-in-start-2",
            behavior,
            props: .supervision(strategy: strategy)
        )

        try probe.expectMessage("starting")
        ref.tell("test")
        try probe.expectMessage("started:test")
        ref.tell("boom")
        try probe.expectMessage("setup:failing")
        try probe.expectMessage("starting")
        ref.tell("test")
        try probe.expectMessage("started:test")
    }

    internal func assertSetupFailureLimit(failureMode: FailureMode) throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)

        let strategy: SupervisionStrategy = .restart(atMost: 5, within: .seconds(10))
        let behavior: Behavior<String> = .setup { _ in
            probe.tell("starting")
            try failureMode.fail()
            return .receiveMessage { message in
                probe.tell("started:\(message)")
                return .same
            }
        }

        let ref: ActorRef<String> = try system.spawn(
            "fail-in-start-3",
            behavior,
            props: .supervision(strategy: strategy)
        )
        probe.watch(ref)
        for _ in 1...5 {
            try probe.expectMessage("starting")
        }
        try probe.expectTerminated(ref)
    }

    internal func testRestartThrowsShouldHandleFailureWhenInterpretingStart() throws {
        try self.assertSetupFailureRestart(failureMode: .throwing)
    }

    internal func testRestartThrowsShouldHandleFailureWhenInterpretingStartAfterFailure() throws {
        try self.assertSetupFailureAfterRestart(failureMode: .throwing)
    }

    internal func testRestartThrowsShouldFailAfterMaxFailuresInSetup() throws {
        try self.assertSetupFailureLimit(failureMode: .throwing)
    }
}
