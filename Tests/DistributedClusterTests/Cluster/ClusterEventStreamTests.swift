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
import Logging
import NIO
import XCTest

@testable import DistributedCluster

internal final class ClusterEventStreamTests: SingleClusterSystemXCTestCase, @unchecked Sendable {
    internal let memberA: Cluster.Member =
        Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(systemName: "System", host: "1.1.1.1", port: 7_337),
                nid: .random()
            ),
            status: .operational
        )
    internal let memberB: Cluster.Member =
        Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(systemName: "System", host: "2.2.2.2", port: 8_228),
                nid: .random()
            ),
            status: .operational
        )

    internal func test_clusterEventStream_shouldNotCauseDeadLettersOnLocalOnlySystem() throws {
        _ = try self.system.spawn(
            "anything",
            Behavior<String>.setup { context in
                context.log.info("Hello there!")
                return .stop
            }
        )

        try self.logCapture.awaitLogContaining(self.testKit, text: "Hello there!")
        self.logCapture.grep("Dead letter").shouldBeEmpty()
    }

    internal func test_clusterEventStream_shouldCollapseEventsAndOfferASnapshotToLateSubscribers() async throws {
        let firstProbe: ActorTestProbe<Cluster.Event> = self.testKit.makeTestProbe(expecting: Cluster.Event.self)
        let secondProbe: ActorTestProbe<Cluster.Event> = self.testKit.makeTestProbe(expecting: Cluster.Event.self)

        let eventStream: ClusterEventStream = ClusterEventStream(system, customName: "testClusterEvents")

        await eventStream.subscribeAndWait(firstProbe.ref)  // sub before first -> up was published
        await eventStream.publish(.membershipChange(.init(member: self.memberA, toStatus: .operational)))
        await eventStream.subscribeAndWait(secondProbe.ref)
        await eventStream.publish(.membershipChange(.init(member: self.memberB, toStatus: .operational)))

        // ==== p1 ---------------------

        switch try firstProbe.expectMessage() {
        case .snapshot(.empty):
            ()  // ok

        default:
            throw firstProbe.error("Expected a snapshot first")
        }
        switch try firstProbe.expectMessage() {
        case .membershipChange(let change):
            change.node.shouldEqual(self.memberA.node)

        default:
            throw firstProbe.error("Expected a membershipChange")
        }
        switch try firstProbe.expectMessage() {
        case .membershipChange(let change):
            change.node.shouldEqual(self.memberB.node)

        default:
            throw firstProbe.error("Expected a membershipChange")
        }

        // ==== p2 ---------------------

        switch try secondProbe.expectMessage() {
        case .snapshot(let snapshot):
            snapshot.member(self.memberA.node).shouldEqual(self.memberA)
            ()  // ok

        default:
            throw secondProbe.error("Expected a snapshot first")
        }
        switch try secondProbe.expectMessage() {
        case .membershipChange(let change):
            change.node.shouldEqual(self.memberB.node)

        default:
            throw secondProbe.error("Expected a membershipChange")
        }
    }

    internal func test_clusterEventStream_collapseManyEventsIntoSnapshot() async throws {
        let firstProbe: ActorTestProbe<Cluster.Event> = self.testKit.makeTestProbe(expecting: Cluster.Event.self)

        let eventStream: ClusterEventStream = ClusterEventStream(system, customName: "testClusterEvents")

        await eventStream.publish(.membershipChange(.init(member: self.memberA, toStatus: .joining)))
        await eventStream.publish(.membershipChange(.init(member: self.memberA, toStatus: .operational)))
        await eventStream.publish(.membershipChange(.init(member: self.memberB, toStatus: .joining)))
        await eventStream.publish(.membershipChange(.init(member: self.memberB, toStatus: .operational)))
        await eventStream.subscribeAndWait(firstProbe.ref)

        // ==== p1 ---------------------

        switch try firstProbe.expectMessage() {
        case .snapshot(let snapshot):
            let members: [Cluster.Member] = snapshot.members(atLeast: .joining)
            Set(members).shouldEqual(Set([self.memberA, self.memberB]))

        default:
            throw firstProbe.error("Expected a snapshot with all the data")
        }

        try firstProbe.expectNoMessage(for: .milliseconds(100))
    }

    internal func test_clusterEventStream_collapseManyEventsIntoSnapshot_async() async {
        let eventStream: ClusterEventStream = ClusterEventStream(system, customName: "testClusterEvents")

        // Publish events to change membership
        await eventStream.publish(.membershipChange(.init(member: self.memberA, toStatus: .joining)))
        await eventStream.publish(.membershipChange(.init(member: self.memberA, toStatus: .operational)))
        await eventStream.publish(.membershipChange(.init(member: self.memberB, toStatus: .joining)))
        await eventStream.publish(.membershipChange(.init(member: self.memberB, toStatus: .operational)))

        // .snapshot is sent on subscribe
        for await event in eventStream {
            switch event {
            case .snapshot(let snapshot):
                let members: [Cluster.Member] = snapshot.members(atLeast: .joining)
                Set(members).shouldEqual(Set([self.memberA, self.memberB]))
                return

            default:
                return XCTFail("Expected a snapshot with all the data to be the first received event")
            }
        }
    }
}
