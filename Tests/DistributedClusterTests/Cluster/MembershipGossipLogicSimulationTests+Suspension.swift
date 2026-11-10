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

extension MembershipGossipLogicSimulationTests {
    internal func test_shouldEventuallySuspendGossiping() async throws {
        let systemA: ClusterSystem = await setUpNode("A") { settings in
            settings.enabled = true
        }

        let systemB: ClusterSystem = await setUpNode("B")
        let systemC: ClusterSystem = await setUpNode("C")

        let initialGossipState: String =
            """
            A.up B.joining C.joining
            A: A@3 B@3 C@3
            B: A@3 B@3 C@3
            C: A@3 B@3 C@3
            """

        try self.gossipSimulationTest(
            runs: 10,
            setUpPeers: { () in
                [
                    try self.makeInitialGossip(initialGossipState, on: systemA, file: #file, line: #line),
                    try self.makeInitialGossip(initialGossipState, on: systemB, file: #file, line: #line),
                    try self.makeInitialGossip(initialGossipState, on: systemC, file: #file, line: #line),
                ]
            },
            updateLogic: { _ in
                let logicA: MembershipGossipLogic = try self.logic("A")

                // We simulate that `A` noticed it's the leader and moved `B` and `C` .up
                logicA.receiveLocalGossipUpdate(
                    try Cluster.MembershipGossip.parse(
                        """
                        A.up B.up C.up
                        A: A@5 B@3 C@3
                        B: A@3 B@3 C@3
                        C: A@3 B@3 C@3
                        """,
                        owner: systemA.cluster.node,
                        nodes: self.clusterNodes,
                        file: #file,
                        line: #line
                    )
                )
            },
            stopRunWhen: { logics, _ in
                logics.allSatisfy { logic in
                    logic.selectPeers(self.peers(of: logic)).isEmpty  // no more peers to talk to
                }
            },
            assert: { results in
                try XCTUnwrap(results.roundCounts.max()).shouldBeLessThanOrEqual(4)
                try XCTUnwrap(results.messageCounts.max()).shouldBeLessThanOrEqual(12)
            }
        )
    }
}
