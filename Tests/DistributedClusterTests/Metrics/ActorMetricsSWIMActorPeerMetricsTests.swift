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

import DistributedActorsConcurrencyHelpers
import DistributedActorsTestKit
import MetricsTestKit
import NIO
import XCTest

@testable import CoreMetrics
@testable import DistributedCluster
@testable import Metrics
@testable import SWIM

internal final class ActorMetricsSWIMActorPeerMetricsTests: ClusteredActorSystemsXCTestCase {
    internal let metrics: TestMetrics = TestMetrics()

    override internal func setUp() {
        MetricsSystem.bootstrapInternal(self.metrics)
        super.setUp()
    }

    override internal func tearDown() async throws {
        try await super.tearDown()
        MetricsSystem.bootstrapInternal(NOOPMetricsHandler.instance)
    }

    override internal func configureLogCapture(settings: inout LogCapture.Settings) {
        settings.filterActorPaths = ["/user/swim"]
    }

    internal func test_swimPeer_ping_shouldRemoteMetrics() async throws {
        let originNode: ClusterSystem = await setUpNode("origin") { settings in
            settings.swim.probeInterval = .seconds(30)  // Don't let gossip interfere with the test
        }
        let targetNode: ClusterSystem = await setUpNode("target")

        originNode.cluster.join(endpoint: targetNode.cluster.endpoint)
        try assertAssociated(originNode, withExactly: targetNode.cluster.node)

        guard let origin = originNode.clusterShell?.swimShell else {
            throw testKit(originNode).fail("SWIM shell of [\(originNode)] should not be nil")
        }
        guard let target = targetNode.clusterShell?.swimShell else {
            throw testKit(targetNode).fail("SWIM shell of [\(targetNode)] should not be nil")
        }

        // SWIMActor's sendFirstRemotePing might have been triggered when the nodes
        // are associated. Reset so we get metrics just for our sendPing call.
        // TestTimer has no reset(), so remember how many timings were recorded so far instead
        let timerValuesBefore: Int =
            (try await self.metrics.getSWIMTimer(origin) { $0.pingResponseTime })?.values.count ?? 0
        (try await self.metrics.getSWIMCounter(origin) { $0.messageOutboundCount })?.reset()

        _ = await origin.whenLocal { __secretlyKnownToBeLocal in
            await __secretlyKnownToBeLocal.sendPing(
                to: target.swimNode,
                payload: .none,
                request: (origin: nil, sequenceNumber: nil),
                timeout: .milliseconds(200),
                sequenceNumber: 1
            )
        }

        guard let timer = try await self.metrics.getSWIMTimer(origin, { $0.pingResponseTime }) else {
            throw testKit(originNode).fail("SWIM metrics pingResponseTime should not be nil")
        }
        let timerDescription: String? = timer.lastValue.map { Duration.nanoseconds($0).prettyDescription }
        pinfo(
            "Recorded \(timer): \(String(reflecting: timerDescription))",
            file: #fileID,
            line: #line
        )
        timer.label.shouldEqual("origin.cluster.swim.roundTripTime.ping")
        timer.values.count.shouldBeGreaterThan(timerValuesBefore)
        try XCTUnwrap(timer.lastValue).shouldBeGreaterThan(0)

        guard let counter = try await self.metrics.getSWIMCounter(origin, { $0.messageOutboundCount }) else {
            throw testKit(originNode).fail("SWIM metrics messageOutboundCount should not be nil")
        }
        counter.totalValue.shouldEqual(1)
    }

    // Flaky test, see https://github.com/apple/swift-distributed-actors/issues/1193
    internal func disabledTestSwimPeerPingRequestShouldRemoteMetrics() async throws {
        let originNode: ClusterSystem = await setUpNode("origin") { settings in
            settings.swim.probeInterval = .seconds(30)  // Don't let gossip interfere with the test
        }
        let targetNode: ClusterSystem = await setUpNode("target")
        let throughNode: ClusterSystem = await setUpNode("through")

        originNode.cluster.join(endpoint: throughNode.cluster.endpoint)
        targetNode.cluster.join(endpoint: throughNode.cluster.endpoint)
        try assertAssociated(originNode, withExactly: [targetNode.cluster.node, throughNode.cluster.node])

        guard let origin = originNode.clusterShell?.swimShell else {
            throw testKit(originNode).fail("SWIM shell of [\(originNode)] should not be nil")
        }
        guard let target = targetNode.clusterShell?.swimShell else {
            throw testKit(targetNode).fail("SWIM shell of [\(targetNode)] should not be nil")
        }
        guard let through = throughNode.clusterShell?.swimShell else {
            throw testKit(throughNode).fail("SWIM shell of [\(throughNode)] should not be nil")
        }

        // SWIMActor's sendFirstRemotePing might have been triggered when the nodes
        // are associated. Reset so we get metrics just for our sendPingRequest call.
        (try await self.metrics.getSWIMCounter(origin) { $0.messageOutboundCount })?.reset()

        let directive: SWIM.Instance.SendPingRequestDirective = SWIM.Instance.SendPingRequestDirective(
            target: target.swimNode,
            timeout: .seconds(1),
            requestDetails: [
                .init(peerToPingRequestThrough: through.swimNode, payload: .none, sequenceNumber: 1)
            ]
        )

        _ = await origin.whenLocal { __secretlyKnownToBeLocal in
            await __secretlyKnownToBeLocal.sendPingRequests(directive)
        }

        try await assertPingRequestMetrics(
            origin: origin,
            node: originNode,
            file: #fileID,
            line: #line
        )
    }

    private func assertPingRequestMetrics(
        origin: SWIMActor,
        node: ClusterSystem,
        file: StaticString,
        line: UInt
    ) async throws {
        guard let timerFirst = try await self.metrics.getSWIMTimer(origin, { $0.pingRequestResponseTimeFirst }) else {
            throw testKit(node).fail("SWIM metrics pingRequestResponseTimeFirst should not be nil")
        }
        let timerFirstDescription: String? = timerFirst.lastValue.map { Duration.nanoseconds($0).prettyDescription }
        pinfo(
            "Recorded \(timerFirst): \(String(reflecting: timerFirstDescription))",
            file: file,
            line: line
        )
        timerFirst.label.shouldEqual("origin.cluster.swim.roundTripTime.pingRequest")
        try XCTUnwrap(timerFirst.lastValue).shouldBeGreaterThan(0)

        guard let timerAll = try await self.metrics.getSWIMTimer(origin, { $0.pingRequestResponseTimeAll }) else {
            throw testKit(node).fail("SWIM metrics pingRequestResponseTimeAll should not be nil")
        }
        let timerAllDescription: String? = timerAll.lastValue.map { Duration.nanoseconds($0).prettyDescription }
        pinfo(
            "Recorded \(timerAll): \(String(reflecting: timerAllDescription))",
            file: file,
            line: line
        )
        timerAll.label.shouldEqual("origin.cluster.swim.roundTripTime.pingRequest")
        try XCTUnwrap(timerAll.lastValue).shouldBeGreaterThan(0)

        guard let counter = try await self.metrics.getSWIMCounter(origin, { $0.messageOutboundCount }) else {
            throw testKit(node).fail("SWIM metrics messageOutboundCount should not be nil")
        }
        counter.totalValue.shouldEqual(1)
    }
}

extension TestMetrics {
    internal func getSWIMTimer(
        _ swimShell: SWIMActor,
        _ body: (SWIM.Metrics.ShellMetrics) -> Timer
    ) async throws -> TestTimer? {
        let localTimer: Timer? = await swimShell.whenLocal { __secretlyKnownToBeLocal in
            body(__secretlyKnownToBeLocal.metrics.shell)
        }

        guard let timer = localTimer else {
            return nil
        }

        return try self.expectTimer(timer)
    }

    internal func getSWIMCounter(
        _ swimShell: SWIMActor,
        _ body: (SWIM.Metrics.ShellMetrics) -> Counter
    ) async throws -> TestCounter? {
        let localCounter: Counter? = await swimShell.whenLocal { __secretlyKnownToBeLocal in
            body(__secretlyKnownToBeLocal.metrics.shell)
        }

        guard let counter = localCounter else {
            return nil
        }

        return try self.expectCounter(counter)
    }
}
