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
    internal func test_swim_shouldMarkSuspects_whenPingFailsAndNoOtherNodesCanBeRequested() async throws {
        let firstNode: ClusterSystem = await self.setUpFirst(nil)
        let secondNode: ClusterSystem = await self.setUpSecond(nil)

        firstNode.cluster.join(endpoint: secondNode.cluster.node.endpoint)
        try assertAssociated(firstNode, withExactly: secondNode.cluster.node)

        guard let first = firstNode.clusterShell?.swimShell else {
            throw testKit(firstNode).fail("SWIM shell of [\(firstNode)] should not be nil")
        }
        guard let second = secondNode.clusterShell?.swimShell else {
            throw testKit(secondNode).fail("SWIM shell of [\(secondNode)] should not be nil")
        }

        try await self.configureSWIM(for: first, members: [second])

        let targetPeer: SWIMActor = try SWIMActor.resolve(id: second.id.asRemote, using: firstNode)

        // FIXME: use a non-responsive test probe instead of faking response
        // Fake a failed ping
        _ = await first.whenLocal { localShell in
            _ = localShell.handlePingResponse(
                response: .timeout(
                    target: targetPeer.swimNode,
                    pingRequestOrigin: nil,
                    timeout: .milliseconds(100),
                    sequenceNumber: 13
                ),
                pingRequestOrigin: nil,
                pingRequestSequenceNumber: nil
            )
        }

        try await self.awaitStatus(
            .suspect(incarnation: 0, suspectedBy: [first.swimNode]),
            for: targetPeer,
            on: first,
            within: .seconds(1),
            source: .init(file: #filePath, line: #line, column: #column, function: #function)
        )
    }

    internal func test_swim_shouldMarkSuspects_whenPingFailsAndRequestedNodesFailToPing() async throws {
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

        let throughPeer: SWIMActor = try SWIMActor.resolve(id: second.id.asRemote, using: firstNode)
        let targetPeer: SWIMActor = try SWIMActor.resolve(id: third.id.asRemote, using: firstNode)

        // FIXME: use non-response test probes instead of faking responses
        // Fake a failed ping and ping request
        _ = await first.whenLocal { localShell in
            // `first` got .timeout when pinging `third`, so it sends ping request to `second` for `three`
            _ = localShell.handlePingResponse(
                response: .timeout(
                    target: targetPeer.swimNode,
                    pingRequestOrigin: nil,
                    timeout: .milliseconds(100),
                    sequenceNumber: 13
                ),
                pingRequestOrigin: nil,
                pingRequestSequenceNumber: nil
            )
            // `first` got .timeout from `second` for ping request
            localShell.handlePingRequestResponse(
                response: .timeout(
                    target: targetPeer.swimNode,
                    pingRequestOrigin: first.swimNode,
                    timeout: .milliseconds(100),
                    sequenceNumber: 5
                ),
                pinged: throughPeer.swimNode
            )
        }

        // eventually it will ping/pingRequest and as all the pings (supposedly) time out it should mark as suspect
        try await self.awaitStatus(
            .suspect(incarnation: 0, suspectedBy: [first.swimNode]),
            for: targetPeer,
            on: first,
            within: .seconds(1),
            source: .init(file: #filePath, line: #line, column: #column, function: #function)
        )
    }

    internal func test_swim_shouldNotMarkUnreachable_whenSuspectedByNotEnoughNodes_whenMinTimeoutReached()
        async throws {
        let maxIndependentSuspicions: Int = 10
        let suspicionTimeoutPeriodsMax: Int = 1_000
        let suspicionTimeoutPeriodsMin: Int = 1
        let timeSource: TestTimeSource = TestTimeSource(currentTicks: 1)

        let firstNode: ClusterSystem = await self.setUpFirst { settings in
            settings.swim.timeSourceNow = timeSource.now
            settings.swim.lifeguard.suspicionTimeoutMin = .nanoseconds(suspicionTimeoutPeriodsMin)
            settings.swim.lifeguard.suspicionTimeoutMax = .nanoseconds(suspicionTimeoutPeriodsMax)
            settings.swim.lifeguard.maxIndependentSuspicions = maxIndependentSuspicions
        }

        let secondNode: ClusterSystem = await self.setUpSecond(nil)
        let thirdNode: ClusterSystem = await self.setUpThird(nil)

        firstNode.cluster.join(endpoint: secondNode.cluster.node.endpoint)
        thirdNode.cluster.join(endpoint: secondNode.cluster.node.endpoint)
        try assertAssociated(firstNode, withExactly: [secondNode.cluster.node, thirdNode.cluster.node])
        try assertAssociated(secondNode, withExactly: [firstNode.cluster.node, thirdNode.cluster.node])

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

        let originPeer: SWIMActor = try SWIMActor.resolve(id: third.id.asRemote, using: secondNode)
        let targetPeer: SWIMActor = try SWIMActor.resolve(id: second.id.asRemote, using: firstNode)

        _ = await first.whenLocal { localShell in
            localShell.handlePeriodicProtocolPeriodTick()
        }
        timeSource.tick()

        let suspectStatus: SWIM.Status = .suspect(incarnation: 0, suspectedBy: [first.swimNode])

        _ = try await first.ping(
            origin: originPeer.swimNode,
            payload: .membership([SWIM.Member(node: targetPeer.swimNode, status: suspectStatus, protocolPeriod: 0)]),
            sequenceNumber: 1
        )

        try await self.awaitStatus(
            suspectStatus,
            for: targetPeer,
            on: first,
            within: .seconds(1),
            source: .init(file: #filePath, line: #line, column: #column, function: #function)
        )
        timeSource.tick()
    }
}
