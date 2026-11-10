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

internal class ActorLifecycleTests: SingleClusterSystemXCTestCase {
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: starting actors

    internal func test_spawn_shouldNotAllowStartingWith_Same() throws {
        // since there is no previous behavior to stay "same" name at the same time:

        let thrownError: Error = try shouldThrow {
            let sameBehavior: Behavior<String> = .same
            _ = try self.system.spawn("same", sameBehavior)
        }

        "\(thrownError)".shouldEqual(
            """
            notAllowedAsInitial(DistributedCluster.Behavior<Swift.String>.same)
            """
        )
    }

    internal func test_spawn_shouldNotAllowStartingWith_Unhandled() throws {
        // the purpose of unhandled is to combine with things that can handle, and if we start a raw unhandled
        // it always will be unhandled until we use some signal to make it otherwise... weird edge case which
        // is better avoided all together.
        //
        // We do allow starting with .ignore though since that's like a "blackhole"

        let thrownError: Error = try shouldThrow {
            let unhandledBehavior: Behavior<String> = .unhandled
            try system.spawn("unhandled", unhandledBehavior)
        }

        "\(thrownError)".shouldEqual("notAllowedAsInitial(DistributedCluster.Behavior<Swift.String>.unhandled)")
    }

    internal func test_spawn_shouldNotAllowIllegalActorNames() throws {
        func check(illegalName: String, expectedError: String) throws {
            let err: Error = try shouldThrow {
                let secondValue: Behavior<String> = .ignore

                // more coverage for all the different chars in [[ActorPathTests]]
                try system.spawn(.unique(illegalName), secondValue)
            }
            "\(err)".shouldEqual(expectedError)
        }

        try check(
            illegalName: "hello world",

            expectedError: """
                illegalActorPathElement(name: "hello world", illegal: " ", index: 5)
                """
        )

        try check(
            illegalName: "he//o",

            expectedError: """
                illegalActorPathElement(name: "he//o", illegal: "/", index: 2)
                """
        )
        try check(
            illegalName: "ążŻŌżąć",

            expectedError: """
                illegalActorPathElement(name: "ążŻŌżąć", illegal: "ą", index: 0)
                """
        )
        try check(
            illegalName: "カピバラ",

            expectedError: """
                illegalActorPathElement(name: "カピバラ", illegal: "カ", index: 0)
                """
        )  // ka-pi-ba-ra
    }

    internal func test_spawn_shouldThrowFromMultipleActorsWithTheSamePathBeingSpawned() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let spawner: Behavior<String> = .receive { context, name in
            let fromName: ActorPath = context.path
            let _: ActorRef<Int> = try context.system.spawn(
                "\(name)",

                .setup { context in
                    probe.tell("me:\(context.path) spawned from \(fromName)")
                    return .receiveMessage { _ in .stop }  // keep ignoring
                }
            )
            return .stop
        }
        try system.spawn("a", spawner).tell("charlie")
        try self.system.spawn("b", spawner).tell("charlie")
        try self.system.spawn("c", spawner).tell("charlie")
        try self.system.spawn("d", spawner).tell("charlie")
        try self.system.spawn("e", spawner).tell("charlie")
        try self.system.spawn("f", spawner).tell("charlie")

        let spawnedBy: String = try probe.expectMessage()
        pinfo("Spawned by: \(spawnedBy)", file: #fileID, line: #line)

        try probe.expectNoMessage(for: .milliseconds(200))
    }
}
