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

import Dispatch
import DistributedActorsTestKit
import NIO
import ServiceDiscovery
import XCTest

@testable import DistributedCluster

internal class TestTriggeredServiceDiscovery<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    internal private(set) var defaultLookupTimeout: DispatchTimeInterval = .seconds(3)

    internal let lock: ClusterMutex = .init()

    internal var onNext: (Result<[Instance], Error>) -> Void = { _ in () }
    internal var onComplete: (CompletionReason) -> Void = { _ in () }

    internal let subscribed: BlockingReceptacle<Void> = .init()
    internal let cancelled: BlockingReceptacle<CompletionReason> = .init()

    // ServiceDiscovery requires lookup; this fixture only exercises subscriptions.
    // swiftlint:disable unavailable_function
    internal func lookup(
        _: Service,
        deadline _: DispatchTime?,
        callback _: (Result<[Instance], Error>) -> Void
    ) {
        fatalError("Not used")
    }
    // swiftlint:enable unavailable_function

    internal func subscribe(
        to _: Service,
        onNext nextResultHandler: @escaping (Result<[Instance], Error>) -> Void,
        onComplete completionHandler: @escaping (CompletionReason) -> Void
    ) -> CancellationToken {
        self.lock.synchronized {
            self.onNext = nextResultHandler
            self.onComplete = completionHandler
            subscribed.offerOnce(())
            return .init { reason in
                self.cancelled.offerOnce(reason)
            }
        }
    }

    internal func sendNext(_ element: Result<[Instance], Error>) {
        self.lock.synchronized {
            subscribed.wait(atMost: .seconds(3))
            self.onNext(element)
        }
    }

    internal func complete(_: CompletionReason) {
        self.lock.synchronized {
            subscribed.wait(atMost: .seconds(3))
        }
    }
}

internal final class ClusterDiscoveryTests: SingleClusterSystemXCTestCase {
    internal let firstMember: Cluster.Member =
        Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(systemName: "A", host: "1.1.1.1", port: 7_337),
                nid: .random()
            ),
            status: .operational
        )
    internal let secondMember: Cluster.Member =
        Cluster.Member(
            node: Cluster.Node(
                endpoint: Cluster.Endpoint(systemName: "B", host: "2.2.2.2", port: 8_228),
                nid: .random()
            ),
            status: .operational
        )

    internal func test_discovery_shouldInitiateJoinsToNewlyDiscoveredNodes() throws {
        let discovery: TestTriggeredServiceDiscovery<String, Cluster.Endpoint> =
            TestTriggeredServiceDiscovery<String, Cluster.Endpoint>()
        let settings: ServiceDiscoverySettings = ServiceDiscoverySettings(discovery, service: "example")
        let clusterProbe: ActorTestProbe<ClusterShell.Message> =
            testKit.makeTestProbe(expecting: ClusterShell.Message.self)
        _ = try system.spawn("discovery", DiscoveryShell(settings: settings, cluster: clusterProbe.ref).behavior)

        discovery.subscribed.wait()

        // [A], join A
        discovery.sendNext(.success([self.firstMember.node.endpoint]))
        guard case .command(.handshakeWith(let node1)) = try clusterProbe.expectMessage() else {
            throw testKit.fail(line: #line - 1)
        }
        node1.shouldEqual(self.firstMember.node.endpoint)

        // [A, B], join B
        discovery.sendNext(.success([self.firstMember.node.endpoint, self.secondMember.node.endpoint]))
        guard case .command(.handshakeWith(let node2)) = try clusterProbe.expectMessage() else {
            throw testKit.fail(line: #line - 1)
        }
        node2.shouldEqual(self.secondMember.node.endpoint)
        try clusterProbe.expectNoMessage(
            for: .milliseconds(300)
        )  // index.e. it should not send another join for `firstMember` we already did that
        // sending another join for A would be harmless in general, but let's avoid causing more work for the system?

        // [A, B]; should not really emit like this but even if it did, no reason to issue more joins
        discovery.sendNext(.success([self.firstMember.node.endpoint, self.secondMember.node.endpoint]))
        try clusterProbe.expectNoMessage(for: .milliseconds(200))

        // [A], removals do not cause removals / downs, one could do this via a downing provider if one wanted to
        discovery.sendNext(.success([self.firstMember.node.endpoint]))
        try clusterProbe.expectNoMessage(for: .milliseconds(200))

        // [A, B], B is back, this could mean it's a "new" B, so let's issue a join just to be sure.
        discovery.sendNext(.success([self.firstMember.node.endpoint, self.secondMember.node.endpoint]))
        guard case .command(.handshakeWith(let node3)) = try clusterProbe.expectMessage() else {
            throw testKit.fail(line: #line - 1)
        }
        node3.shouldEqual(self.secondMember.node.endpoint)
    }

    internal func test_discovery_shouldInitiateJoinsToStaticNodes() throws {
        let nodes: Set = Set([self.firstMember, self.secondMember].map(\.node.endpoint))
        let settings: ServiceDiscoverySettings = ServiceDiscoverySettings(static: Set(nodes))
        let clusterProbe: ActorTestProbe<ClusterShell.Message> =
            testKit.makeTestProbe(expecting: ClusterShell.Message.self)
        _ = try system.spawn("discovery", DiscoveryShell(settings: settings, cluster: clusterProbe.ref).behavior)

        for message in try clusterProbe.expectMessages(count: 2) {
            guard case .command(.handshakeWith(let node)) = message else {
                throw testKit.fail(line: #line - 1)
            }
            node.shouldBeIn(nodes)
        }
    }

    internal func test_discovery_shouldHandleMappingsWhenDiscoveryHasItsOwnTypes() throws {
        struct ExampleK8sService: Hashable {
            let name: String
        }

        struct ExampleK8sInstance: Hashable {
            let endpoint: Cluster.Endpoint
        }

        let discovery: TestTriggeredServiceDiscovery<ExampleK8sService, ExampleK8sInstance> =
            TestTriggeredServiceDiscovery<ExampleK8sService, ExampleK8sInstance>()
        let settings: ServiceDiscoverySettings = ServiceDiscoverySettings(
            discovery,
            service: ExampleK8sService(name: "example")
        ) { instance in instance.endpoint }
        let clusterProbe: ActorTestProbe<ClusterShell.Message> =
            testKit.makeTestProbe(expecting: ClusterShell.Message.self)
        _ = try system.spawn("discovery", DiscoveryShell(settings: settings, cluster: clusterProbe.ref).behavior)

        discovery.subscribed.wait()

        // [A], join A
        discovery.sendNext(.success([ExampleK8sInstance(endpoint: self.firstMember.node.endpoint)]))
        guard case .command(.handshakeWith(let node1)) = try clusterProbe.expectMessage() else {
            throw testKit.fail(line: #line - 1)
        }
        node1.shouldEqual(self.firstMember.node.endpoint)

        // [A, B], join B
        discovery.sendNext(
            .success(
                [
                    ExampleK8sInstance(
                        endpoint: self.firstMember.node.endpoint
                    ),
                    ExampleK8sInstance(endpoint: self.secondMember.node.endpoint),
                ]
            )
        )
        guard case .command(.handshakeWith(let node2)) = try clusterProbe.expectMessage() else {
            throw testKit.fail(line: #line - 1)
        }
        node2.shouldEqual(self.secondMember.node.endpoint)
        try clusterProbe.expectNoMessage(
            for: .milliseconds(300)
        )  // index.e. it should not send another join for `firstMember` we already did that
    }

    internal func test_discovery_stoppingActor_shouldCancelSubscription() throws {
        let discovery: TestTriggeredServiceDiscovery<String, Cluster.Endpoint> =
            TestTriggeredServiceDiscovery<String, Cluster.Endpoint>()
        let settings: ServiceDiscoverySettings = ServiceDiscoverySettings(discovery, service: "example")
        let clusterProbe: ActorTestProbe<ClusterShell.Message> =
            testKit.makeTestProbe(expecting: ClusterShell.Message.self)
        let ref: ActorRef<DiscoveryShell.Message> = try system.spawn(
            "discovery",
            DiscoveryShell(settings: settings, cluster: clusterProbe.ref).behavior
        )

        discovery.subscribed.wait()

        // [A], join A
        discovery.sendNext(.success([self.firstMember.node.endpoint]))
        guard case .command(.handshakeWith(let node1)) = try clusterProbe.expectMessage() else {
            throw testKit.fail(line: #line - 1)
        }
        node1.shouldEqual(self.firstMember.node.endpoint)

        ref.sendSystemMessage(.stop)
        _ = discovery.cancelled.wait(atMost: .seconds(3))
    }
}
