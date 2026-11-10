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
import SWIM
import XCTest

@testable import DistributedCluster

internal final class SWIMSerializationTests: SingleClusterSystemXCTestCase {
    internal func test_serializationOf_ack() async throws {
        let targetNode: ClusterSystem = await setUpNode("target") { settings in
            settings.enabled = true
        }

        guard let target = targetNode.clusterShell?.swimShell else {
            throw testKit.fail("SWIM shell of [\(targetNode)] should not be nil")
        }

        let payload: SWIM.GossipPayload =
            .membership([.init(node: target.swimNode, status: .alive(incarnation: 0), protocolPeriod: 0)])
        let pingReq: SWIM.PingResponse =
            .ack(target: target.swimNode, incarnation: 1, payload: payload, sequenceNumber: 13)
        try self.shared_serializationRoundtrip(pingReq)
    }

    internal func test_serializationOf_nack() async throws {
        let targetNode: ClusterSystem = await setUpNode("target") { settings in
            settings.enabled = true
        }

        guard let target = targetNode.clusterShell?.swimShell else {
            throw testKit.fail("SWIM shell of [\(targetNode)] should not be nil")
        }

        let pingReq: SWIM.PingResponse = .nack(target: target.swimNode, sequenceNumber: 13)
        try self.shared_serializationRoundtrip(pingReq)
    }

    internal func shared_serializationRoundtrip<T: ProtobufRepresentable>(_ obj: T) throws {
        let serialized: Serialization.Serialized = try self.system.serialization.serialize(obj)
        let deserialized: T = try self.system.serialization.deserialize(as: T.self, from: serialized)
        "\(obj)".shouldEqual("\(deserialized)")
    }
}
