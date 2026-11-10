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
import ClusterMembership
import Distributed
import DistributedActorsConcurrencyHelpers  // for TimeSource
import Foundation
import MetricsTestKit
import XCTest

@testable import CoreMetrics
@testable import DistributedActorsTestKit
@testable import DistributedCluster
@testable import Metrics
@testable import SWIM

extension SWIMActorClusteredTests {
    internal func test_swim_shouldSendGossipInAck() async throws {
        let firstNode: ClusterSystem = await self.setUpFirst(nil)
        let secondNode: ClusterSystem = await self.setUpSecond(nil)

        firstNode.cluster.join(endpoint: secondNode.cluster.node.endpoint)
        try assertAssociated(firstNode, withExactly: secondNode.cluster.node)
        try assertAssociated(secondNode, withExactly: firstNode.cluster.node)

        guard let first = firstNode.clusterShell?.swimShell else {
            throw testKit(firstNode).fail("SWIM shell of [\(firstNode)] should not be nil")
        }
        guard let second = secondNode.clusterShell?.swimShell else {
            throw testKit(secondNode).fail("SWIM shell of [\(secondNode)] should not be nil")
        }

        try await self.configureSWIM(for: first, members: [second])

        let secondPeer: SWIMActor = try SWIMActor.resolve(id: second.id.asRemote, using: firstNode)
        let response: SWIM.PingResponse =
            try await first.ping(origin: secondPeer.swimNode, payload: .none, sequenceNumber: 1)

        guard case .ack(_, _, .membership(let members), _) = response else {
            throw testKit(firstNode).fail("Expected gossip with membership, but got \(response)")
        }

        members.count.shouldEqual(2)
        members.shouldContain { $0.node == secondPeer.swimNode && $0.status == .alive(incarnation: 0) }
        members.shouldContain { $0.node == first.swimNode && $0.status == .alive(incarnation: 0) }
    }

    internal func test_SWIMShell_shouldMonitorJoinedClusterMembers() async throws {
        let localNode: ClusterSystem = await self.setUpFirst(nil)
        let remoteNode: ClusterSystem = await self.setUpSecond(nil)

        localNode.cluster.join(endpoint: remoteNode.cluster.node.endpoint)

        guard let local = localNode.clusterShell?.swimShell else {
            throw testKit(localNode).fail("SWIM shell of [\(localNode)] should not be nil")
        }
        guard let remote = remoteNode.clusterShell?.swimShell else {
            throw testKit(remoteNode).fail("SWIM shell of [\(remoteNode)] should not be nil")
        }

        let remotePeer: SWIMActor = try SWIMActor.resolve(id: remote.id.asRemote, using: localNode)
        try await self.awaitStatus(
            .alive(incarnation: 0),
            for: remotePeer,
            on: local,
            within: .seconds(1),
            source: .init(file: #filePath, line: #line, column: #column, function: #function)
        )
    }
}
