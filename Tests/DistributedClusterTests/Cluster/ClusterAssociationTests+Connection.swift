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
    internal func test_boundServer_shouldAcceptAssociate() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()

        first.cluster.join(endpoint: second.cluster.node.endpoint)

        try assertAssociated(first, withExactly: second.cluster.node)
        try assertAssociated(second, withExactly: first.cluster.node)
    }

    internal func test_boundServer_shouldAcceptAssociate_raceFromBothNodes() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()
        let thirdNode: ClusterSystem = await setUpNode("node-3")
        let fourthNode: ClusterSystem = await setUpNode("node-4")
        let fifthNode: ClusterSystem = await setUpNode("node-5")
        let sixthNode: ClusterSystem = await setUpNode("node-6")

        first.cluster.join(endpoint: second.cluster.node.endpoint)
        second.cluster.join(endpoint: first.cluster.node.endpoint)

        thirdNode.cluster.join(endpoint: first.cluster.node.endpoint)
        first.cluster.join(endpoint: thirdNode.cluster.node.endpoint)

        fourthNode.cluster.join(endpoint: first.cluster.node.endpoint)
        first.cluster.join(endpoint: fourthNode.cluster.node.endpoint)

        fifthNode.cluster.join(endpoint: first.cluster.node.endpoint)
        first.cluster.join(endpoint: fifthNode.cluster.node.endpoint)

        sixthNode.cluster.join(endpoint: first.cluster.node.endpoint)
        first.cluster.join(endpoint: sixthNode.cluster.node.endpoint)

        try assertAssociated(first, withAtLeast: second.cluster.node)
        try assertAssociated(second, withAtLeast: first.cluster.node)
    }

    internal func test_handshake_shouldNotifyOnSuccess() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()

        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))

        try assertAssociated(first, withExactly: second.cluster.node)
        try assertAssociated(second, withExactly: first.cluster.node)
    }

    internal func test_handshake_shouldNotifySuccessWhenAlreadyConnected() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()

        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))

        try assertAssociated(first, withExactly: second.cluster.node)
        try assertAssociated(second, withExactly: first.cluster.node)

        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))

        try assertAssociated(first, withExactly: second.cluster.node)
        try assertAssociated(second, withExactly: first.cluster.node)
    }

    internal func test_clusterControl_joined_shouldCauseJoiningAttempt() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()

        try await first.cluster.joined(endpoint: second.cluster.endpoint, within: .seconds(3))
        try await second.cluster.joined(endpoint: first.cluster.endpoint, within: .seconds(3))

        try assertAssociated(first, withExactly: second.cluster.node)
        try await assertMemberStatus(on: first, node: second.cluster.node, atLeast: .operational, within: .seconds(3))

        try assertAssociated(second, withExactly: first.cluster.node)
        try await assertMemberStatus(on: second, node: first.cluster.node, atLeast: .operational, within: .seconds(3))
    }

    internal func test_association_sameAddressNodeJoin_shouldOverrideExistingNode() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()

        let secondName: String = second.cluster.node.endpoint.systemName
        let secondPort: Int = second.cluster.node.port

        let firstEventsProbe: ActorTestProbe<Cluster.Event> =
            self.testKit(first).makeTestProbe(expecting: Cluster.Event.self)
        let secondEventsProbe: ActorTestProbe<Cluster.Event> =
            self.testKit(second).makeTestProbe(expecting: Cluster.Event.self)
        await first.cluster.events.subscribeAndWait(firstEventsProbe.ref)
        await second.cluster.events.subscribeAndWait(secondEventsProbe.ref)

        first.cluster.join(endpoint: second.cluster.node.endpoint)

        try assertAssociated(first, withExactly: second.cluster.node)
        try assertAssociated(second, withExactly: first.cluster.node)

        let oldSecond: ClusterSystem = second
        let shutdown: ClusterSystem.Shutdown = try oldSecond.shutdown()  // terminate second node
        try await shutdown.wait()

        let secondReplacement: ClusterSystem = await setUpNode(secondName + "-REPLACEMENT") { settings in
            settings.bindPort = secondPort
        }

        let secondReplacementEventsProbe: ActorTestProbe<Cluster.Event> =
            self.testKit(secondReplacement).makeTestProbe(expecting: Cluster.Event.self)
        await secondReplacement.cluster.events.subscribeAndWait(secondReplacementEventsProbe.ref)
        await second.cluster.events.subscribeAndWait(secondReplacementEventsProbe.ref)

        // the new replacement node is now going to initiate a handshake with 'first' which knew about the previous
        // instance (oldSecond) on the same node; It should accept this new handshake, and ban the previous node.
        secondReplacement.cluster.join(endpoint: first.cluster.node.endpoint)

        // verify we are associated ONLY with the appropriate nodes now;
        try assertAssociated(first, withExactly: [secondReplacement.cluster.node])
        try assertAssociated(secondReplacement, withExactly: [first.cluster.node])
    }

    internal func test_association_shouldAllowSendingToSecondReference() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()

        let probeOnSecond: ActorTestProbe<String> = self.testKit(second).makeTestProbe(expecting: String.self)
        let refOnSecondSystem: ActorRef<String> = try second.spawn(
            "secondAcquaintance",
            .receiveMessage { message in
                probeOnSecond.tell("forwarded:\(message)")
                return .same
            }
        )

        first.cluster.join(endpoint: second.cluster.node.endpoint)

        try assertAssociated(first, withExactly: second.settings.bindNode)

        // first we manually construct the "right second path"; Don't do this in normal production code
        let uniqueSecondAddress: ActorID =
            ActorID(
                local: second.cluster.node,
                path: refOnSecondSystem.path,
                incarnation: refOnSecondSystem.id.incarnation
            )
        // to then obtain a second ref ON the `system`, meaning that the node within uniqueSecondAddress is a second one
        let resolvedRef: ActorRef<String> =
            self.resolveRef(first, type: String.self, id: uniqueSecondAddress, on: second)
        // the resolved ref is a first resource on the `system` and points via the right association to the second actor
        // inside system `second`. Sending messages to a ref constructed like this will make the messages go over
        // remoting.
        resolvedRef.tell("HELLO")

        try probeOnSecond.expectMessage("forwarded:HELLO")
    }

    internal func test_ignore_attemptToSelfJoinANode() async throws {
        let alone: ClusterSystem = await setUpNode("alone")

        alone.cluster.join(endpoint: alone.cluster.node.endpoint)  // "self join", should simply be ignored

        let testKit: ActorTestKit = self.testKit(alone)
        try await testKit.eventually(within: .seconds(3)) {
            let snapshot: Cluster.Membership = await alone.cluster.membershipSnapshot
            if snapshot.count != 1 {
                throw TestError("Expected membership to include self node, was: \(snapshot)")
            }
        }
    }
}
