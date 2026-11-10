// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2024 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed
import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

internal final class DaemonJoiningClusteredTests: ClusteredActorSystemsXCTestCase {
    internal var daemon: ClusterDaemon?

    override internal func configureLogCapture(settings: inout LogCapture.Settings) {
        settings.excludeActorPaths = [
            "/system/cluster/swim",
            "/system/cluster/gossip",
            "/system/replicator",
            "/system/cluster",
            "/system/clusterEvents",
            "/system/cluster/leadership",
            "/system/nodeDeathWatcher",

            "/dead/system/receptionist-ref",  // FIXME(distributed): it should simply be quiet
        ]
        settings.excludeGrep = [
            "timer"
        ]
    }

    override internal func tearDown() async throws {
        try await super.tearDown()
        try await self.daemon?.shutdown().wait()
    }

    internal func test_shouldPerformLikeASeedNode() async throws {
        self.daemon = await ClusterSystem.startClusterDaemon()
        let first: ClusterSystem = await self.setUpNode("first") { settings in
            settings.discovery = .clusterd
        }

        let second: ClusterSystem = await self.setUpNode("second") { settings in
            settings.discovery = .clusterd
        }
        try await ensureNodes(atLeast: .operational, nodes: [first.cluster.node, second.cluster.node])
    }
}
