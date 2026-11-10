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
    internal func test_cachedSecondControlsWithSameNodeID_shouldNotOverwriteEachOther() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair()
        second.cluster.join(endpoint: first.cluster.node.endpoint)

        try assertAssociated(first, withExactly: second.cluster.node)

        let thirdSystem: ClusterSystem = await setUpNode("third") { settings in
            settings.nid = second.settings.nid
            settings.endpoint.port = 9_119
        }

        thirdSystem.cluster.join(endpoint: first.cluster.node.endpoint)
        try assertAssociated(first, withExactly: [second.cluster.node, thirdSystem.settings.bindNode])

        first.clusterShell?.testingAssociations.count.shouldEqual(2)
    }

    internal func test_sendingMessageToNotYetAssociatedNode_mustCauseAssociationAttempt() async throws {
        let first: ClusterSystem = await setUpNode("first")
        let second: ClusterSystem = await setUpNode("second")

        // actor on `second` node
        let secondProbe: ActorTestProbe<String> = self.testKit(second).makeTestProbe(expecting: String.self)
        let secondOne: ActorRef<String> = try second.spawn(
            "second-1",
            .receive { _, message in
                secondProbe.tell("Got:\(message)")
                return .same
            }
        )
        let secondFullAddress: ActorID =
            ActorID(remote: second.cluster.node, path: secondOne.path, incarnation: secondOne.id.incarnation)

        // we somehow obtained a ref to secondOne (on second node) without associating second yet
        // e.g. another node sent us that ref; This must cause buffering of sends to second and an association to be
        // created.

        let resolveContext: ResolveContext<String> = ResolveContext<String>(id: secondFullAddress, system: first)
        let ref: ActorRef<String> = first.resolve(context: resolveContext)

        try assertNotAssociated(system: first, node: second.cluster.node)
        try assertNotAssociated(system: second, node: first.cluster.node)

        // will be buffered until associated, and then delivered:
        ref.tell("Hello 1")
        ref.tell("Hello 2")
        ref.tell("Hello 3")

        try secondProbe.expectMessage("Got:Hello 1")
        try secondProbe.expectMessage("Got:Hello 2")
        try secondProbe.expectMessage("Got:Hello 3")

        try assertAssociated(first, withExactly: second.cluster.node)
        try assertAssociated(second, withExactly: first.cluster.node)
    }

    internal func test_down_self_shouldChangeMembershipSelfToBeDown() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            // as otherwise we can't inspect if we really changed the status to .down,
            // as we might shutdown too quickly :-)
            settings.onDownAction = .disabled
        }

        second.cluster.join(endpoint: first.cluster.node.endpoint)
        try assertAssociated(first, withExactly: second.cluster.node)

        // down myself
        first.cluster.down(endpoint: first.cluster.node.endpoint)

        let firstProbe: ActorTestProbe<Cluster.Membership> =
            self.testKit(first).makeTestProbe(expecting: Cluster.Membership.self)
        let secondProbe: ActorTestProbe<Cluster.Membership> =
            self.testKit(second).makeTestProbe(expecting: Cluster.Membership.self)

        // we we down first on first, it should become down there:
        try self.testKit(first).eventually(within: .seconds(3)) {
            first.cluster.ref.tell(.query(.currentMembership(firstProbe.ref)))
            let firstMembership: Cluster.Membership = try firstProbe.expectMessage()

            guard let selfMember = firstMembership.member(first.cluster.node) else {
                throw self.testKit(
                    second
                ).error("No self member in membership! Wanted: \(first.cluster.node)", line: #line - 1)
            }
            guard selfMember.status == .down else {
                throw self.testKit(
                    first
                ).error("Wanted self member to be DOWN, but was: \(selfMember)", line: #line - 1)
            }
        }
        try await self.assertMemberStatus(on: first, node: first.cluster.node, is: .down, within: .seconds(3))

        // and the second node should also notice
        try self.testKit(second).eventually(within: .seconds(3)) {
            second.cluster.ref.tell(.query(.currentMembership(secondProbe.ref)))
            let secondMembership: Cluster.Membership = try secondProbe.expectMessage()

            // and the first node should also propagate the Down information to the second node
            // although this may be a best effort since the first can just shut down if it wanted to,
            // this scenario assumes a graceful leave though:

            guard let firstMemberObservedOnSecond = secondMembership.member(first.cluster.node) else {
                throw self.testKit(
                    second
                ).error("\(second) does not know about the \(first.cluster.node) at all...!", line: #line - 1)
            }

            guard firstMemberObservedOnSecond.status == .down else {
                throw self.testKit(
                    second
                ).error(
                    """
                    Wanted to see \(first.cluster.node) as DOWN on \(second), \
                    but was still: \(firstMemberObservedOnSecond)
                    """,
                    line: #line - 1
                )
            }
        }
    }
}
