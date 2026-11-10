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
import Foundation  // for pretty printing JSON
import Logging
import NIO
import XCTest

@testable import DistributedCluster

internal final class MembershipSerializationTests: SingleClusterSystemXCTestCase {
    internal lazy var context: Serialization.Context = Serialization.Context(
        log: system.log,
        system: system,
        allocator: system.settings.serialization.allocator
    )

    internal func test_serializationOf_membership() throws {
        let membership: Cluster.Membership = [
            Cluster.Member(
                node: Cluster.Node(
                    endpoint: Cluster.Endpoint(systemName: "first", host: "1.1.1.1", port: 7_337),
                    nid: .random()
                ),
                status: .operational
            ),
            Cluster.Member(
                node: Cluster.Node(
                    endpoint: Cluster.Endpoint(systemName: "second", host: "2.2.2.2", port: 8_228),
                    nid: .random()
                ),
                status: .down
            ),
        ]

        let proto: Cluster.Membership.ProtobufRepresentation = try membership.toProto(context: self.context)
        let back: Cluster.Membership = try Cluster.Membership(fromProto: proto, context: self.context)

        back.shouldEqual(membership)
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Measuring serialization sizes

    internal func test_gossip_serialization() throws {
        let members: [Cluster.Member] = try (1...15).map { id in
            Cluster.Member(
                node: Cluster.Node(
                    endpoint: Cluster.Endpoint(systemName: "\(id)", host: "1.1.1.\(id)", port: 1_111),
                    nid: .init(
                        try XCTUnwrap(UInt64("\(id)\(id)\(id)\(id)"))
                    )  // pretend a real-ish looking ID, but be easier to read
                ),
                status: .operational
            )
        }

        let nodes: [Cluster.Node] = members.map(\.node)

        let gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            1.joining 2.joining 3.joining 4.up 5.up 6.up 7.up 8.up 9.down 10.down 11.up 12.up 13.up 14.up 15.up
            1: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            2: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            3: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            4: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            5: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            6: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            7: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            8: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            9: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            10: 1:4 2:4 3:4 4:6 5:7 6:7 7:8 8:8 9:12 10:12 11:8 12:8 13:8 14:9 15:6
            """,
            owner: XCTUnwrap(nodes.first),
            nodes: nodes,
            file: #file,
            line: #line
        )

        let serialized: Serialization.Serialized = try system.serialization.serialize(gossip)

        pnote("\(serialized.buffer.readData().stringDebugDescription())", file: #fileID, line: #line)
        pinfo("Serialized size: \(serialized.buffer.count) bytes", file: #fileID, line: #line)
        pinfo("  Manifest.serializerID: \(serialized.manifest.serializerID)", file: #fileID, line: #line)
        pinfo("  Manifest.hint:         \(optional: serialized.manifest.hint)", file: #fileID, line: #line)

        serialized.manifest.serializerID.shouldEqual(Serialization.SerializerID.protobufRepresentable)
        serialized.buffer.count.shouldEqual(2_105)

        let back: Cluster.MembershipGossip =
            try system.serialization.deserialize(as: Cluster.MembershipGossip.self, from: serialized)
        "\(pretty: back)".shouldStartWith(prefix: "\(pretty: gossip)")  // nicer human readable error
        back.shouldEqual(gossip)  // the actual soundness check
    }
}
