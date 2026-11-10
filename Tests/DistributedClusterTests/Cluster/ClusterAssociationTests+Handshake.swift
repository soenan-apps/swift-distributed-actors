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
import NIO
import XCTest

@testable import DistributedCluster

extension ClusterAssociationTests {
    internal func test_concurrentIncomingAndOutgoingHandshakes_shareAssociation() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()

        // here we attempt to make a race where the nodes race to join each other
        // again, only one association should be created.
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))
        second.cluster.ref.tell(.command(.handshakeWith(first.cluster.node.endpoint)))

        try assertAssociated(first, withExactly: second.settings.bindNode)
        try assertAssociated(second, withExactly: first.settings.bindNode)
    }

    internal func test_concurrentOutgoingHandshakes_shareAssociation() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()

        // we issue two handshakes quickly after each other, both should succeed but there should only be one
        // association established (!)
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))

        try assertAssociated(first, withExactly: second.settings.bindNode)
        try assertAssociated(second, withExactly: first.settings.bindNode)
    }

    internal func test_handshake_shouldKeepTryingUntilOtherNodeBindsPort() async throws {
        let first: ClusterSystem = await setUpNode("first")

        let secondPort: Int = first.cluster.node.endpoint.port + 10
        // second is NOT started, but we already ask first to handshake with the second one (which will fail, though
        // the node should keep trying)
        let secondEndpoint: Cluster.Endpoint =
            Cluster.Endpoint(systemName: "second", host: "127.0.0.1", port: secondPort)

        first.cluster.join(endpoint: secondEndpoint)
        sleep(3)  // we give it some time to keep failing to connect, so the second node is not yet started

        let second: ClusterSystem = await setUpNode("second") { settings in
            settings.bindPort = secondPort
        }

        try assertAssociated(first, withExactly: second.cluster.node)
        try assertAssociated(second, withExactly: first.cluster.node)
    }

    internal func test_handshake_shouldStopTryingWhenMaxAttemptsExceeded() async throws {
        let first: ClusterSystem = await setUpNode("first") { settings in
            settings.handshakeReconnectBackoff = Backoff.exponential(
                initialInterval: .milliseconds(100),
                maxAttempts: 2
            )
        }

        let secondPort: Int = first.cluster.node.endpoint.port + 10
        // second is NOT started, but we already ask first to handshake with the second one (which will fail, though
        // the node should keep trying)
        let secondEndpoint: Cluster.Endpoint =
            Cluster.Endpoint(systemName: "second", host: "127.0.0.1", port: secondPort)

        first.cluster.join(endpoint: secondEndpoint)
        sleep(1)  // we give it some time to keep failing to connect (and exhaust the retries)

        let logs: LogCapture = self.capturedLogs(of: first)
        try logs.awaitLogContaining(
            self.testKit(first),
            text: "Giving up on handshake with node [sact://second@127.0.0.1:9011]"
        )
    }

    internal func test_handshake_shouldNotAssociateWhenRejected() async throws {
        let first: ClusterSystem = await setUpNode("first") { settings in
            settings.protocolVersion.major += 1  // handshake will be rejected on major version difference
        }

        let second: ClusterSystem = await setUpNode("second")

        first.cluster.join(endpoint: second.cluster.node.endpoint)

        try assertNotAssociated(system: first, node: second.cluster.node)
        try assertNotAssociated(system: second, node: first.cluster.node)
    }

    internal func test_handshake_shouldNotifyOnRejection() async throws {
        let first: ClusterSystem = await setUpNode("first") { settings in
            settings.protocolVersion.major += 1  // handshake will be rejected on major version difference
        }

        let second: ClusterSystem = await setUpNode("second")

        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))

        try assertNotAssociated(system: first, node: second.cluster.node)
        try assertNotAssociated(system: second, node: first.cluster.node)

        try self.capturedLogs(of: first)
            .awaitLogContaining(
                self.testKit(first),
                text: "Handshake rejected by [sact://second@127.0.0.1:9002], reason: incompatibleProtocolVersion"
            )
    }

    internal func test_handshake_shouldRejectIfNodeIsLeavingOrDown() async throws {
        let first: ClusterSystem = await setUpNode("first") { settings in
            settings.onDownAction = .disabled  // don't shutdown this node (keep process alive)
        }

        let second: ClusterSystem = await setUpNode("second")

        first.cluster.down(endpoint: first.cluster.node.endpoint)

        let testKit: ActorTestKit = self.testKit(first)
        try await testKit.eventually(within: .seconds(3)) {
            let snapshot: Cluster.Membership = await first.cluster.membershipSnapshot
            if let selfMember = snapshot.member(first.cluster.node) {
                if selfMember.status == .down {
                    ()  // good
                } else {
                    throw testKit.error(
                        """
                        Expecting \(first.cluster.node) to become [.down] but was \(selfMember.status). Membership: \
                        \(pretty: snapshot)
                        """
                    )
                }
            } else {
                throw testKit.error("No self member for \(first.cluster.node)! Membership: \(pretty: snapshot)")
            }
        }

        // now we try to join the "already down" node; it should reject any such attempts
        second.cluster.ref.tell(.command(.handshakeWith(first.cluster.node.endpoint)))

        try assertNotAssociated(system: first, node: second.cluster.node)
        try assertNotAssociated(system: second, node: first.cluster.node)

        try self.capturedLogs(of: second)
            .awaitLogContaining(
                self.testKit(second),
                text: "Handshake rejected by [sact://first@127.0.0.1:9001], reason: Node already leaving cluster."
            )
    }
}
