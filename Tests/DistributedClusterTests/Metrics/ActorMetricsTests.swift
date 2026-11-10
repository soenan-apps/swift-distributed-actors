// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2020 Apple Inc. and the Swift Distributed Actors project authors
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
import Foundation
import MetricsTestKit
import NIO
import XCTest

@testable import CoreMetrics
@testable import DistributedCluster
@testable import Metrics

internal final class ActorMetricsTests: ClusteredActorSystemsXCTestCase {
    internal let metrics: TestMetrics = TestMetrics()

    override internal func setUp() {
        super.setUp()
        MetricsSystem.bootstrapInternal(self.metrics)
    }

    override internal func tearDown() async throws {
        try await super.tearDown()
        MetricsSystem.bootstrapInternal(NOOPMetricsHandler.instance)
    }

    internal func test_serialization_reportsMetrics() async throws {
        let first: ClusterSystem = await setUpNode("first")
        let second: ClusterSystem = await setUpNode("second")

        let ref: ActorRef<String> = try first.spawn(
            "measuredActor",
            Behavior.receive { _, _ in
                .same
            },
            props: .metrics(group: "measuredActorGroup", measure: [.deserialization])
        )

        let remoteRef: ActorRef<String> = second.resolve(ref: ref, onSystem: first)
        remoteRef.tell("Hello!")

        sleep(6)
        try self.metrics.expectGauge("first.measuredActorGroup.deserialization.size").lastValue?.shouldEqual(6)
    }

    internal func test_mailboxCount_reportsMetrics() async throws {
        let first: ClusterSystem = await setUpNode("first")

        let one: ActorRef<String> = try first.spawn(
            "measuredActor",
            Behavior.receive { _, _ in .same },
            props: .metrics(group: "measuredActorGroup", measure: [.mailbox])
        )

        for _ in 0...256 {
            one.tell("hello")
        }

        sleep(5)
        // Processing overlaps delivery, so assert the final drained count rather than a transient maximum.
        try self.metrics.expectGauge("first.measuredActorGroup.mailbox.count").lastValue.shouldEqual(0)
    }
}
