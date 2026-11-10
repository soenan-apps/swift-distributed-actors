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
import DistributedActorsTestKit
import Foundation
import MetricsTestKit
import XCTest

@testable import CoreMetrics
@testable import DistributedCluster
@testable import Metrics
@testable import SWIM

extension SWIMActorClusteredTests {
    internal func test_swim_shouldNotIncreaseProbeInterval_whenLowMultiplier() async throws {
        let firstNode: ClusterSystem = await self.setUpFirst { settings in
            settings.swim.lifeguard.maxLocalHealthMultiplier = 1
            settings.swim.pingTimeout = .microseconds(1)
            // interval should be configured in a way that multiplied by a low LHA counter it fail wail the test
            settings.swim.probeInterval = .milliseconds(100)
        }

        let secondNode: ClusterSystem = await self.setUpSecond(nil)

        firstNode.cluster.join(endpoint: secondNode.cluster.endpoint)
        try assertAssociated(firstNode, withExactly: secondNode.cluster.node)

        guard let first = firstNode.clusterShell?.swimShell else {
            throw testKit(firstNode).fail("SWIM shell of [\(firstNode)] should not be nil")
        }
        guard let second = secondNode.clusterShell?.swimShell else {
            throw testKit(secondNode).fail("SWIM shell of [\(secondNode)] should not be nil")
        }

        try await self.configureSWIM(for: first, members: [second])

        // SWIMActor's sendFirstRemotePing might have been triggered when the nodes
        // are associated. Reset so we get metrics just for the test call.
        (try await self.metrics.getSWIMCounter(second) { $0.messageInboundCount })?.reset()

        _ = await first.whenLocal { localShell in
            localShell.handlePeriodicProtocolPeriodTick()
        }

        try await self.assertMessageInboundCount(of: second, atLeast: 2, within: .milliseconds(300))
    }

    internal func test_swim_shouldRespondWithAckToPing() async throws {
        let firstNode: ClusterSystem = await self.setUpFirst(nil)
        let secondNode: ClusterSystem = await self.setUpSecond(nil)

        guard let first = firstNode.clusterShell?.swimShell else {
            throw testKit(firstNode).fail("SWIM shell of [\(firstNode)] should not be nil")
        }
        guard let second = secondNode.clusterShell?.swimShell else {
            throw testKit(secondNode).fail("SWIM shell of [\(secondNode)] should not be nil")
        }

        let originPeer: SWIMActor = try SWIMActor.resolve(id: second.id.asRemote, using: firstNode)
        let response: SWIM.PingResponse =
            try await first.ping(origin: originPeer.swimNode, payload: .none, sequenceNumber: 13)

        guard case let .ack(pinged, incarnation, _, _) = response else {
            throw testKit(firstNode).fail("Expected ack, but got \(response)")
        }

        pinged.shouldEqual(first.swimNode)
        incarnation.shouldEqual(0)
    }

    internal func test_swim_shouldRespondWithNackToPingReq_whenNoResponseFromTarget() async throws {
        let firstNode: ClusterSystem = await self.setUpFirst(nil)
        let secondNode: ClusterSystem = await self.setUpSecond(nil)
        let thirdNode: ClusterSystem = await self.setUpThird(nil)

        firstNode.cluster.join(endpoint: secondNode.cluster.node.endpoint)
        thirdNode.cluster.join(endpoint: secondNode.cluster.node.endpoint)
        try assertAssociated(firstNode, withExactly: secondNode.cluster.node)

        guard let first = firstNode.clusterShell?.swimShell else {
            throw testKit(firstNode).fail("SWIM shell of [\(firstNode)] should not be nil")
        }
        guard let second = secondNode.clusterShell?.swimShell else {
            throw testKit(secondNode).fail("SWIM shell of [\(secondNode)] should not be nil")
        }
        guard let third = thirdNode.clusterShell?.swimShell else {
            throw testKit(thirdNode).fail("SWIM shell of [\(thirdNode)] should not be nil")
        }

        try await self.configureSWIM(for: first, members: [second, third])

        // FIXME: use a non-responsive test probe instead of real system
        // Down the node so it doesn't respond to ping
        try thirdNode.shutdown()
        try await self.ensureNodes(.removed, nodes: thirdNode.cluster.node, on: secondNode)

        let originPeer: SWIMActor = try SWIMActor.resolve(id: first.id.asRemote, using: secondNode)
        let targetPeer: SWIMActor = try SWIMActor.resolve(id: third.id.asRemote, using: secondNode)
        // `first` pings `third` through `second`. `third` is down so `second` will return nack for ping request.
        let response: SWIM.PingResponse =
            try await second.pingRequest(
                target: targetPeer.swimNode,
                pingRequestOrigin: originPeer.swimNode,
                payload: .none,
                sequenceNumber: 13
            )

        guard case .nack = response else {
            throw testKit(firstNode).fail("Expected nack, but got \(response)")
        }
    }

    internal func test_swim_shouldPingRandomMember() async throws {
        let firstNode: ClusterSystem = await self.setUpFirst(nil)
        let secondNode: ClusterSystem = await self.setUpSecond(nil)
        let thirdNode: ClusterSystem = await self.setUpThird(nil)

        firstNode.cluster.join(endpoint: secondNode.cluster.node.endpoint)
        thirdNode.cluster.join(endpoint: secondNode.cluster.node.endpoint)
        try assertAssociated(firstNode, withExactly: secondNode.cluster.node)

        guard let first = firstNode.clusterShell?.swimShell else {
            throw testKit(firstNode).fail("SWIM shell of [\(firstNode)] should not be nil")
        }
        guard let second = secondNode.clusterShell?.swimShell else {
            throw testKit(secondNode).fail("SWIM shell of [\(secondNode)] should not be nil")
        }
        guard let third = thirdNode.clusterShell?.swimShell else {
            throw testKit(thirdNode).fail("SWIM shell of [\(thirdNode)] should not be nil")
        }

        try await self.configureSWIM(for: first, members: [second, third])

        // SWIMActor's sendFirstRemotePing might have been triggered when the nodes
        // are associated. Reset so we get metrics just for the test calls.
        (try await self.metrics.getSWIMCounter(second) { $0.messageInboundCount })?.reset()
        (try await self.metrics.getSWIMCounter(third) { $0.messageInboundCount })?.reset()

        _ = await first.whenLocal { localShell in
            localShell.handlePeriodicProtocolPeriodTick()
            localShell.handlePeriodicProtocolPeriodTick()
        }

        // `first` should send ping to both `second` and `third` after two ticks
        try await withThrowingTaskGroup(of: Void.self) { group in
            for swimShell in [second, third] {
                group.addTask {
                    try await self.assertMessageInboundCount(of: swimShell, atLeast: 1, within: .seconds(2))
                }
            }
            // loop explicitly to propagagte any error that might have been thrown
            try await group.waitForAll()
        }
    }

    internal func test_swim_shouldPingSpecificMemberWhenRequested() async throws {
        let firstNode: ClusterSystem = await self.setUpFirst(nil)
        let secondNode: ClusterSystem = await self.setUpSecond(nil)
        let thirdNode: ClusterSystem = await self.setUpThird(nil)

        guard let first = firstNode.clusterShell?.swimShell else {
            throw testKit(firstNode).fail("SWIM shell of [\(firstNode)] should not be nil")
        }
        guard let second = secondNode.clusterShell?.swimShell else {
            throw testKit(secondNode).fail("SWIM shell of [\(secondNode)] should not be nil")
        }
        guard let third = thirdNode.clusterShell?.swimShell else {
            throw testKit(thirdNode).fail("SWIM shell of [\(thirdNode)] should not be nil")
        }

        try await self.configureSWIM(for: first, members: [second, third])

        let originPeer: SWIMActor = try SWIMActor.resolve(id: first.id.asRemote, using: secondNode)
        let targetPeer: SWIMActor = try SWIMActor.resolve(id: third.id.asRemote, using: secondNode)
        // `first` pings `third` through `second`
        let response: SWIM.PingResponse =
            try await second.pingRequest(
                target: targetPeer.swimNode,
                pingRequestOrigin: originPeer.swimNode,
                payload: .none,
                sequenceNumber: 13
            )

        guard case let .ack(pinged, incarnation, _, _) = response else {
            throw testKit(firstNode).fail("Expected ack, but got \(response)")
        }

        pinged.shouldEqual(third.swimNode)
        incarnation.shouldEqual(0)
    }
}
