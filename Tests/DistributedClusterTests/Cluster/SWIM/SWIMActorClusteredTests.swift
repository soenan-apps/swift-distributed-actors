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

internal final class TestTimeSource: @unchecked Sendable {
    internal let baseInstant: ContinuousClock.Instant = .now
    internal let currentTicks: UnsafeAtomic<UInt64>

    /// starting from 1 to ensure .distantPast is already expired
    internal init(currentTicks: UInt64) {
        self.currentTicks = .create(currentTicks)
    }

    internal func now() -> ContinuousClock.Instant {
        self.baseInstant.advanced(by: .nanoseconds(Int(self.currentTicks.load(ordering: .relaxed))))
    }

    internal func tick() {
        _ = self.currentTicks.loadThenWrappingIncrement(by: 100, ordering: .relaxed)
    }
}

internal final class SWIMActorClusteredTests: ClusteredActorSystemsXCTestCase {
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

    internal func setUpFirst(_ modifySettings: ((inout ClusterSystemSettings) -> Void)?) async -> ClusterSystem {
        await super.setUpNode("first", modifySettings)
    }

    internal func setUpSecond(_ modifySettings: ((inout ClusterSystemSettings) -> Void)?) async -> ClusterSystem {
        await super.setUpNode("second", modifySettings)
    }

    internal func setUpThird(_ modifySettings: ((inout ClusterSystemSettings) -> Void)?) async -> ClusterSystem {
        await super.setUpNode("third", modifySettings)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: utility functions

    internal func configureSWIM(for swimShell: SWIMActor, members: [SWIMActor]) async throws {
        var memberStatus: [SWIMActor: SWIM.Status] = [:]
        for member in members {
            memberStatus[member] = .alive(incarnation: 0)
        }
        try await self.configureSWIM(for: swimShell, members: memberStatus)
    }

    internal func configureSWIM(for swimShell: SWIMActor, members: [SWIMActor: SWIM.Status]) async throws {
        await swimShell.whenLocal { localShell in
            localShell.configureSWIM { swim in
                for (member, status) in members {
                    _ = swim.addMember(member.swimNode, status: status)
                }
            }
        }
    }

    internal func assertMessageInboundCount(of swimShell: SWIMActor, atLeast: Int, within: Duration) async throws {
        // FIXME: with test probes we can control the exact number of messages (e.g., probe.expectMessage()),
        // but that's not easy with do with real systems so we check for inbound message count and do at-least
        // instead of exact comparisons.
        let testKit: ActorTestKit = self.testKit(swimShell.actorSystem)

        try await testKit.eventually(within: within) {
            guard let counter = try await self.metrics.getSWIMCounter(swimShell, { $0.messageInboundCount }) else {
                throw testKit.error("SWIM metrics \(swimShell.actorSystem).messageInboundCount should not be nil")
            }

            let total: Int64 = counter.totalValue
            if total < atLeast {
                throw testKit.error(
                    "Expected \(swimShell.actorSystem).messageInboundCount to be at least \(atLeast), was: \(total)"
                )
            }
        }
    }

    internal func awaitStatus(
        _ status: SWIM.Status,
        for peer: SWIMActor,
        on swimShell: SWIMActor,
        within timeout: Duration,
        source: CallSiteInfo
    ) async throws {
        let testKit: ActorTestKit = self.testKit(swimShell.actorSystem)

        try await testKit.eventually(
            within: timeout,
            file: source.file,
            line: source.line,
            column: source.column
        ) {
            let membership: [SWIM.Member] =
                await swimShell.whenLocal { localShell in
                    localShell.membershipState()
                } ?? []

            let otherStatus: SWIM.Status? =
                membership
                .first { $0.node == peer.swimNode }
                .map(\.status)

            guard otherStatus == status else {
                throw testKit.error(
                    "Expected status [\(status)] for [\(peer)], but found \(otherStatus.debugDescription); "
                        + "Membership: \(membership)",
                    file: source.file,
                    line: source.line
                )
            }
        }
    }
}
