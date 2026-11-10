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

extension ActorLeakingTests {
    internal func test_ClusterSystem_shouldNotLeak() async throws {
        #if !SACT_TESTS_LEAKS
        return self.skipLeakTests()
        #else
        // We need to manage the retain cycles with the receptionist better (#831).
        throw XCTSkip(
            "!!! Skipping test \(#function) !!!"
        )

        let initialSystemCount: Int = ClusterSystem.actorSystemInitCounter.load(ordering: .relaxed)

        for number in 1...5 {
            let system: ClusterSystem = await ClusterSystem("Test-\(number)")
            try await system.shutdown().wait()
        }

        ClusterSystem.actorSystemInitCounter.load(ordering: .relaxed).shouldEqual(initialSystemCount)
        #endif  // SACT_TESTS_LEAKS
    }

    internal func test_releasing_ClusterSystem_mustNotLeaveActorsReferringToANilSystemFromContext() async throws {
        #if !SACT_TESTS_LEAKS
        return self.skipLeakTests()
        #else
        var system: ClusterSystem? = await ClusterSystem("FreeMe")  // only "reference from user land" to the system

        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)

        let ref: ActorRef<String> = try XCTUnwrap(system).spawn(
            "echo",
            .receive { context, message in
                    if message == "shutdown" {
                        try context.system.shutdown()
                    }
                    probe.tell("system:\(context.system)")
                    return .same
            }
        )

        ref.tell("x")
        try probe.expectMessage("system:ClusterSystem(FreeMe, sact://FreeMe@127.0.0.1:7337)")

        // clear the strong reference from "user land"
        system = nil

        ref.tell("x")
        try probe.expectMessage("system:ClusterSystem(FreeMe, sact://FreeMe@127.0.0.1:7337)")

        ref.tell("shutdown")  // since we lost the `system` reference here we'll ask the actor to stop the system

        #endif  // SACT_TESTS_LEAKS
    }

    internal func test_actor_whichLogsShouldNotCauseLeak_onDisabledLevel() async throws {
        #if !SACT_TESTS_LEAKS
        return self.skipLeakTests()
        #else
        let initialSystemCount: Int = ClusterSystem.actorSystemInitCounter.load(ordering: .relaxed)

        var system: ClusterSystem? = await ClusterSystem("Test") { settings in
            settings.logging.logLevel = .info
        }
        _ = try system?.spawn(
            "logging",
            .setup { context in
                    context.log.trace("Not going to be logged")
                    return .receiveMessage { _ in .same }
            }
        )
        try await system?.shutdown().wait()
        system = nil

        ClusterSystem.actorSystemInitCounter.load(ordering: .relaxed).shouldEqual(initialSystemCount)
        #endif  // SACT_TESTS_LEAKS
    }

    internal func test_actor_whichLogsShouldNotCauseLeak_onEnabled() async throws {
        #if !SACT_TESTS_LEAKS
        return self.skipLeakTests()
        #else
        throw XCTSkip(
            "!!! Skipping test \(#function) !!!"
        )  // we need to manage the retain cycles with the receptionist better

        let initialSystemCount: Int = ClusterSystem.actorSystemInitCounter.load(ordering: .relaxed)

        var system: ClusterSystem? = await ClusterSystem("Test") { settings in
            settings.logging.logLevel = .info
        }
        _ = try system?.spawn(
            "logging",
            .setup { context in
                    context.log.warning("Not going to be logged")
                    return .receiveMessage { _ in .same }
            }
        )
        try await system?.shutdown().wait()
        system = nil

        ClusterSystem.actorSystemInitCounter.load(ordering: .relaxed).shouldEqual(initialSystemCount)
        #endif  // SACT_TESTS_LEAKS
    }
}
