// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedCluster
import Logging
import MultiNodeTestKit

internal distributed actor DistributedEcho {
    internal typealias ActorSystem = ClusterSystem

    @ActorID.Metadata(\.receptionID)
    internal var receptionID: String

    private let greeting: String

    internal init(greeting: String, actorSystem: ActorSystem) async {
        self.actorSystem = actorSystem
        self.greeting = greeting
        self.receptionID = "*"

        await actorSystem.receptionist.checkIn(self)
    }

    internal distributed func echo(name: String) -> String {
        "echo: \(self.greeting)\(name)! (from node: \(self.id.node), id: \(self.id.detailedDescription))"
    }
}

public final class MultiNodeReceptionistTests: MultiNodeTestSuite {
    public enum Nodes: String, MultiNodeNodes {
        case first = "first"
        case second = "second"
        case third = "third"
        case fourth = "fourth"
    }

    public let testReceptionistCheckIn: MultiNodeTest

    public init() {
        self.testReceptionistCheckIn = MultiNodeTest(MultiNodeReceptionistTests.self) { multiNode in
            // *All* nodes spawn an echo actor
            let localEcho: DistributedEcho = await DistributedEcho(
                greeting: "Hi from \(multiNode.system.name), ",
                actorSystem: multiNode.system
            )

            try await multiNode.checkPoint("Spawned actors")

            let expectedCount: Int = Nodes.allCases.count
            var discovered: Set<DistributedEcho> = []
            for try await actor in multiNode.system.receptionist.listing(of: .init(DistributedEcho.self)) {
                multiNode.log.notice("Discovered \(actor.id) from \(actor.id.node)")
                discovered.insert(actor)

                if discovered.count == expectedCount {
                    break
                }
            }

            try await multiNode.checkPoint("All members found \(expectedCount) actors")
            withExtendedLifetime(localEcho) {
                // Keep the local actor registered through the final checkpoint.
            }
        }
    }

    public static func configureMultiNodeTest(settings: inout MultiNodeTestSettings) {
        settings.dumpNodeLogs = .always

        settings.logCapture.excludeGrep = [
            "SWIMActor.swift", "SWIMInstance.swift",
            "Gossiper+Shell.swift",
        ]

        settings.installPrettyLogger = true
    }

    public static func configureActorSystem(settings: inout ClusterSystemSettings) {
        settings.logging.logLevel = .debug

        settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 3)
    }
}
