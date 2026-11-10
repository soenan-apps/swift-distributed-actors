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

internal distributed actor TheSingleton: ClusterSingleton {
    internal typealias ActorSystem = ClusterSystem

    private let greeting: String

    internal init(greeting: String, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.greeting = greeting
    }

    internal distributed func greet(name: String) -> String {
        "\(self.greeting) \(name)! (from node: \(self.id.node), id: \(self.id.detailedDescription))"
    }
}

public final class MultiNodeClusterSingletonTests: MultiNodeTestSuite {
    public enum Nodes: String, MultiNodeNodes {
        case first = "first"
        case second = "second"
        case third = "third"
        case fourth = "fourth"
    }

    internal static var singletonSettings: ClusterSingletonSettings {
        var settings: ClusterSingletonSettings = ClusterSingletonSettings()
        settings.allocationStrategy = .byLeadership
        settings.allocationTimeout = .seconds(15)
        return settings
    }

    public let testSingletonFromManyNodes: MultiNodeTest

    public init() {
        self.testSingletonFromManyNodes = MultiNodeTest(MultiNodeClusterSingletonTests.self) { multiNode in
            let singletonName: String = "the-one"

            // All nodes run the same code to "host" the singleton (with a different greeting each)
            let ref: TheSingleton = try await multiNode.system.singleton.host(
                name: singletonName,
                settings: Self.singletonSettings
            ) { actorSystem in
                TheSingleton(greeting: "Hello-\(actorSystem.name)", actorSystem: actorSystem)
            }

            try await multiNode.checkPoint("Hosted singleton")
            let reply: String = try await ref.greet(name: "Hello from \(multiNode.system.name)")
            print("[ON: \(multiNode.system.name)] Got reply: \(reply)")

            try await multiNode.checkPoint("Got reply from singleton")
            // Since now all nodes have made a message exchange with the singleton, we can exit this process.
            // Keep the host alive until every node has finished its call.
        }
    }

    public static func configureMultiNodeTest(settings: inout MultiNodeTestSettings) {
        settings.dumpNodeLogs = .always

        settings.logCapture.excludeGrep = [
            "SWIMActor.swift", "SWIMInstance.swift",
            "OperationLogDistributedReceptionist.swift",
            "Gossiper+Shell.swift",
        ]

        settings.installPrettyLogger = true
    }

    public static func configureActorSystem(settings: inout ClusterSystemSettings) {
        settings.logging.logLevel = .debug

        settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 3)
    }
}
