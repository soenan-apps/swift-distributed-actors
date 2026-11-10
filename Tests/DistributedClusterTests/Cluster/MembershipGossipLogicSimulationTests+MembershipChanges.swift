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
    private static let initialFewGossip: String =
        """
        A.up B.joining C.joining D.joining E.joining F.joining G.joining H.joining I.joining J.joining
        A: A@9 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@5
        B: A@5 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@5
        C: A@3 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@5
        D: A@2 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@1
        E: A@2 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@1
        F: A@2 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@1
        G: A@2 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@1
        H: A@2 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@1
        I: A@2 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@1
        J: A@2 B@3 C@3 D@5 E@5 F@5 G@5 H@5 I@5 J@1
        """

    private static let initialNewGossip: String =
        """
        D.joining E.joining F.joining G.joining H.joining I.joining J.joining
        D: D@5 E@5 F@5 G@5 H@5 I@5 J@5
        E: D@5 E@5 F@5 G@5 H@5 I@5 J@5
        F: D@5 E@5 F@5 G@5 H@5 I@5 J@5
        G: D@5 E@5 F@5 G@5 H@5 I@5 J@5
        H: D@5 E@5 F@5 G@5 H@5 I@5 J@5
        I: D@5 E@5 F@5 G@5 H@5 I@5 J@5
        J: D@5 E@5 F@5 G@5 H@5 I@5 J@5
        """

    internal func test_avgRounds_manyNodes() async throws {
        let systemA: ClusterSystem = await setUpNode("A") { settings in
            settings.enabled = true
        }

        let systemB: ClusterSystem = await setUpNode("B")
        let systemC: ClusterSystem = await setUpNode("C")
        let systemD: ClusterSystem = await setUpNode("D")
        let systemE: ClusterSystem = await setUpNode("E")
        let systemF: ClusterSystem = await setUpNode("F")
        let systemG: ClusterSystem = await setUpNode("G")
        let systemH: ClusterSystem = await setUpNode("H")
        let systemI: ClusterSystem = await setUpNode("I")
        let systemJ: ClusterSystem = await setUpNode("J")

        let allSystems: [ClusterSystem] = [
            systemA, systemB, systemC, systemD, systemE,
            systemF, systemG, systemH, systemI, systemJ,
        ]

        try self.gossipSimulationTest(
            runs: 1,
            setUpPeers: { () in
                [
                    try self.makeInitialGossip(Self.initialFewGossip, on: systemA, file: #file, line: #line),
                    try self.makeInitialGossip(Self.initialFewGossip, on: systemB, file: #file, line: #line),
                    try self.makeInitialGossip(Self.initialFewGossip, on: systemC, file: #file, line: #line),

                    try self.makeInitialGossip(Self.initialNewGossip, on: systemD, file: #file, line: #line),
                    try self.makeInitialGossip(Self.initialNewGossip, on: systemE, file: #file, line: #line),
                    try self.makeInitialGossip(Self.initialNewGossip, on: systemF, file: #file, line: #line),
                    try self.makeInitialGossip(Self.initialNewGossip, on: systemG, file: #file, line: #line),
                    try self.makeInitialGossip(Self.initialNewGossip, on: systemH, file: #file, line: #line),
                    try self.makeInitialGossip(Self.initialNewGossip, on: systemI, file: #file, line: #line),
                    try self.makeInitialGossip(Self.initialNewGossip, on: systemJ, file: #file, line: #line),
                ]
            },
            updateLogic: { _ in
                try self.updateManyNodeMembership(on: systemA, joining: systemD)
            },
            stopRunWhen: { logics, _ in
                // keep gossiping until all members become .up and converged
                logics.allSatisfy { $0.latestGossip.converged() }
                    && logics.allSatisfy { currentLogic in
                        currentLogic.latestGossip.membership.count(withStatus: .operational) == allSystems.count
                    }
            },
            assert: { results in
                results.roundCounts.max()?.shouldBeLessThanOrEqual(3)
                results.messageCounts.max()?.shouldBeLessThanOrEqual(10)
            }
        )
    }
    private func updateManyNodeMembership(on systemA: ClusterSystem, joining systemD: ClusterSystem) throws {
        let logicA: MembershipGossipLogic = try self.logic("A")
        let logicD: MembershipGossipLogic = try self.logic("D")

        logicA.receiveLocalGossipUpdate(
            try Cluster.MembershipGossip.parse(
                """
                A.up B.up C.up D.up E.up F.up G.up H.up I.up J.up
                A: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                B: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                C: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                D: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                E: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                F: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                G: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                H: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                I: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                J: A@20 B@16 C@16 D@16 E@16 F@16 G@16 H@16 I@16 J@16
                """,
                owner: systemA.cluster.node,
                nodes: self.clusterNodes,
                file: #file,
                line: #line
            )
        )

        // they're trying to join
        logicD.receiveLocalGossipUpdate(
            try Cluster.MembershipGossip.parse(
                """
                A.up B.up C.up D.joining E.joining F.joining G.joining H.joining I.joining J.joining
                A: A@11 B@16 C@16 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                B: A@12 B@11 C@11 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                C: A@12 B@11 C@11 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                D: A@12 B@11 C@11 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                E: A@12 B@11 C@11 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                F: A@12 B@11 C@11 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                G: A@12 B@11 C@11 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                H: A@12 B@11 C@11 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                I: A@12 B@11 C@11 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                J: A@12 B@11 C@11 D@9 E@13 F@13 G@13 H@13 I@13 J@13
                """,
                owner: systemD.cluster.node,
                nodes: self.clusterNodes,
                file: #file,
                line: #line
            )
        )
    }

}
