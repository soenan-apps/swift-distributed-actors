// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
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

internal final class ClusterEventsSerializationTests: SingleClusterSystemXCTestCase {
    internal lazy var context: Serialization.Context = Serialization.Context(
        log: system.log,
        system: system,
        allocator: system.settings.serialization.allocator
    )

    internal func test_serializationOf_membershipChange() throws {
        let change: Cluster.MembershipChange =
            Cluster.MembershipChange(
                node: Cluster.Node(
                    endpoint: Cluster.Endpoint(systemName: "first", host: "1.1.1.1", port: 7_337),
                    nid: .random()
                ),
                previousStatus: .leaving,
                toStatus: .removed
            )
        let event: Cluster.Event = Cluster.Event.membershipChange(change)

        let proto: Cluster.Event.ProtobufRepresentation = try event.toProto(context: self.context)
        let back: Cluster.Event = try Cluster.Event(fromProto: proto, context: self.context)

        back.shouldEqual(event)
    }

    internal func test_serializationOf_leadershipChange() throws {
        let old: Cluster.Member =
            Cluster.Member(
                node: Cluster.Node(
                    endpoint: Cluster.Endpoint(systemName: "first", host: "1.1.1.1", port: 7_337),
                    nid: .random()
                ),
                status: .joining
            )
        let new: Cluster.Member =
            Cluster.Member(
                node: Cluster.Node(
                    endpoint: Cluster.Endpoint(systemName: "first", host: "1.2.2.1", port: 2_222),
                    nid: .random()
                ),
                status: .operational
            )
        let event: Cluster.Event =
            .leadershipChange(try XCTUnwrap(Cluster.LeadershipChange(oldLeader: old, newLeader: new)))

        let proto: Cluster.Event.ProtobufRepresentation = try event.toProto(context: self.context)
        let back: Cluster.Event = try Cluster.Event(fromProto: proto, context: self.context)

        back.shouldEqual(event)
    }
}
