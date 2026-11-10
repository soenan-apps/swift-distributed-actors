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
import NIOSSL
import XCTest

@testable import DistributedCluster

internal final class ClusterOnDownActionTests: ClusteredActorSystemsXCTestCase {
    internal func test_onNodeDowned_performShutdown() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await self.setUpPair { settings in
            settings.onDownAction = .gracefulShutdown(delay: .milliseconds(300))
        }

        try await self.joinNodes(node: first, with: second)

        second.cluster.down(endpoint: first.cluster.node.endpoint)

        try self.capturedLogs(of: first).awaitLogContaining(self.testKit(first), text: "Self node was marked [.down]!")

        try self.testKit(first).eventually(within: .seconds(3)) {
            guard first.isShuttingDown else {
                throw TestError(
                    "System \(first) was not shutting down. "
                        + "It was marked down and the default onDownAction should have triggered!"
                )
            }
        }
    }

    internal func test_onNodeDowned_configuredNoop_doNothing() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.onDownAction = .disabled
        }

        try await self.joinNodes(node: first, with: second)

        second.cluster.down(endpoint: first.cluster.node.endpoint)

        try self.capturedLogs(of: first).awaitLogContaining(self.testKit(first), text: "Self node was marked [.down]!")

        first.isShuttingDown.shouldBeFalse()
    }
}
