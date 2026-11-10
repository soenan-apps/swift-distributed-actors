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
import OrderedCollections

/// Defines participant nodes and the configuration used by a multi-node suite.
public protocol MultiNodeTestSuite {
    /// Enumeration identifying all participating nodes.
    associatedtype Nodes: MultiNodeNodes
    init()
    /// Applies actor system settings before node startup.
    static func configureActorSystem(settings: inout ClusterSystemSettings)
    /// Starts an actor system using the supplied settings.
    static func startNode(settings: ClusterSystemSettings) async throws -> ClusterSystem
    /// Applies runner settings before execution.
    static func configureMultiNodeTest(settings: inout MultiNodeTestSettings)
}

extension MultiNodeTestSuite {
    /// Suite lookup key used by the runner.
    public static var key: String {
        "\(Self.self)".split(separator: ".").last.map(String.init) ?? ""
    }

    internal var nodeNames: [String] {
        Nodes.allCases.map(\.rawValue)
    }

    /// Starts the default actor system for a node.
    public static func startNode(settings: ClusterSystemSettings) async -> ClusterSystem {
        await ClusterSystem(settings: settings)
    }

}
