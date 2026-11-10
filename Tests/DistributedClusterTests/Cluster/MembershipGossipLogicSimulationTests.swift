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

internal final class MembershipGossipLogicSimulationTests: ClusteredActorSystemsXCTestCase {
    private typealias MembershipGossipRef =
        ActorRef<GossipShell<Cluster.MembershipGossip, Cluster.MembershipGossip>.Message>

    internal struct GossipSimulationResults {
        internal let runs: Int
        internal var roundCounts: [Int]
        internal var messageCounts: [Int]
    }

    internal var systems: [ClusterSystem] {
        super.nodes
    }

    internal var clusterNodes: [Cluster.Node] {
        super.nodes.map(\.cluster.node)
    }

    internal var mockPeers: [AddressableActorRef] = []
    internal var logics: [MembershipGossipLogic] = []

    internal var gossips: [Cluster.MembershipGossip] {
        self.logics.map(\.latestGossip)
    }

    override internal func configureActorSystem(settings: inout ClusterSystemSettings) {
        settings.enabled = false  // not actually clustering, just need a few nodes
    }

    override internal func configureLogCapture(settings: inout LogCapture.Settings) {
        settings.filterActorPaths = [
            "/user/peer"
        ]
    }

    internal func system(_ id: String) throws -> ClusterSystem {
        try XCTUnwrap(self.systems.first { $0.name == id })
    }

    internal func logic(_ id: String) throws -> MembershipGossipLogic {
        try XCTUnwrap(self.logics.first { $0.localNode.endpoint.systemName == id })
    }

    private func makeLogic(
        _ system: ClusterSystem,
        _ probe: ActorTestProbe<Cluster.MembershipGossip>
    ) -> MembershipGossipLogic {
        MembershipGossipLogic(
            GossipLogicContext<Cluster.MembershipGossip, Cluster.MembershipGossip>(
                ownerContext: self.testKit(system).makeFakeContext(),
                gossipIdentifier: StringGossipIdentifier("membership")
            ),
            notifyOnGossipRef: probe.ref
        )
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Simulation Tests

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Simulation test infra

    private func simulateGossipRound(messageCounts: inout [Int], log: Logger) throws {
        messageCounts.append(0)  // make a counter for this run

        // we shuffle the gossips to simulate the slight timing differences -- not always will the "first" node be
        // the first where the timers trigger
        // and definitely not always will it always _remain_ the first to be gossiping; there may be others still
        // gossiping around spreading their "not super complete"
        // information.
        let participatingGossips: [MembershipGossipLogic] = self.logics.shuffled()
        for logic in participatingGossips {
            let selectedPeers: [AddressableActorRef] = logic.selectPeers(self.peers(of: logic))
            log.notice("[\(logic.nodeName)] selected peers: \(selectedPeers.map(\.id.node.endpoint.systemName))")

            for targetPeer in selectedPeers {
                messageCounts[messageCounts.endIndex - 1] += 1

                let targetGossip: Cluster.MembershipGossip? = logic.makePayload(target: targetPeer)
                if let gossip = targetGossip {
                    log.notice(
                        "    \(logic.nodeName) -> \(targetPeer.id.node.endpoint.systemName)",
                        metadata: [
                            "gossip": Logger.MetadataValue.pretty(gossip)
                        ]
                    )

                    let targetLogic: MembershipGossipLogic = try self.selectLogic(targetPeer)
                    let maybeAck: Cluster.MembershipGossip? =
                        try targetLogic.receiveGossip(gossip, from: self.peer(logic))
                    log.notice(
                        "updated [\(targetPeer.id.node.endpoint.systemName)]",
                        metadata: [
                            "gossip": Logger.MetadataValue.pretty(targetLogic.latestGossip)
                        ]
                    )

                    if let ack = maybeAck {
                        log.notice(
                            "    \(logic.nodeName) <- \(targetPeer.id.node.endpoint.systemName) (ack)",
                            metadata: [
                                "ack": Logger.MetadataValue.pretty(ack)
                            ]
                        )
                        try logic.receiveAcknowledgement(ack, from: self.peer(targetLogic), confirming: gossip)
                    }
                }
            }
        }
    }

    internal func gossipSimulationTest(
        runs: Int,
        setUpPeers: () throws -> [Cluster.MembershipGossip],
        updateLogic: ([MembershipGossipLogic]) throws -> Void,
        stopRunWhen: ([MembershipGossipLogic], GossipSimulationResults) throws -> Bool,
        assert: (GossipSimulationResults) throws -> Void
    ) throws {
        var roundCounts: [Int] = []
        var messageCounts: [Int] = []

        var results: GossipSimulationResults = GossipSimulationResults(
            runs: 0,
            roundCounts: roundCounts,
            messageCounts: messageCounts
        )

        let initialGossips: [Cluster.MembershipGossip] = try setUpPeers()
        let firstSystem: ClusterSystem = try XCTUnwrap(self.systems.first)
        self.mockPeers = try self.systems.map { system -> MembershipGossipRef in
            let ref: MembershipGossipRef =
                try system.spawn("peer", .receiveMessage { _ in .same })
            return firstSystem.resolve(context: .init(id: ref.id.asRemote, system: firstSystem))
        }.map(\.asAddressable)

        var log: Logger = firstSystem.log
        log[metadataKey: "actor/path"] = "/user/peer"  // mock actor path for log capture

        for _ in 1...runs {
            // initialize with user provided gossips
            self.logics = try initialGossips.map { initialGossip in
                let system: ClusterSystem = try self.system(initialGossip.owner.systemName)
                let probe: ActorTestProbe<Cluster.MembershipGossip> =
                    self.testKit(system).makeTestProbe(expecting: Cluster.MembershipGossip.self)
                let logic: MembershipGossipLogic = self.makeLogic(system, probe)
                logic.receiveLocalGossipUpdate(initialGossip)
                return logic
            }

            try updateLogic(self.logics)

            var rounds: Int = 0
            log.notice("~~~~~~~~~~~~ new gossip instance ~~~~~~~~~~~~")
            while try !stopRunWhen(self.logics, results) {
                rounds += 1
                log.notice("Next gossip round (\(rounds))...")
                try self.simulateGossipRound(messageCounts: &messageCounts, log: log)

                if rounds > 20 {
                    throw TestError("Too many gossip rounds detected! This is definitely wrong.")
                }

                results = .init(
                    runs: runs,
                    roundCounts: roundCounts,
                    messageCounts: messageCounts
                )
            }

            roundCounts += [rounds]
        }

        self.logSimulationResults(
            runs: runs, roundCounts: roundCounts, messageCounts: messageCounts, file: #fileID, line: #line
        )

        try assert(results)
    }

    private func logSimulationResults(
        runs: Int, roundCounts: [Int], messageCounts: [Int], file: StaticString, line: UInt
    ) {
        pinfo("Finished [\(runs)] simulation runs", file: file, line: line)
        pinfo(
            "    Rounds: \(roundCounts) (\(Double(roundCounts.reduce(0, +)) / Double(runs)) avg)",
            file: file,
            line: line
        )
        pinfo(
            "  Messages: \(messageCounts) (\(Double(messageCounts.reduce(0, +)) / Double(runs)) avg)",
            file: file,
            line: line
        )
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Support functions

    internal func makeInitialGossip(
        _ dsl: String, on system: ClusterSystem, file: StaticString, line: UInt
    ) throws -> Cluster.MembershipGossip {
        try Cluster.MembershipGossip.parse(
            dsl, owner: system.cluster.node, nodes: self.clusterNodes, file: file, line: line
        )
    }

    internal func peers(of logic: MembershipGossipLogic) -> [AddressableActorRef] {
        Array(self.mockPeers.filter { $0.id.node != logic.localNode })
    }

    internal func selectLogic(_ peer: AddressableActorRef) throws -> MembershipGossipLogic {
        try XCTUnwrap(self.logics.first { $0.localNode == peer.id.node })
    }

    internal func peer(_ logic: MembershipGossipLogic) throws -> AddressableActorRef {
        let nodeName: String = logic.localNode.endpoint.systemName
        return try XCTUnwrap(self.mockPeers.first { $0.id.node.endpoint.systemName == nodeName })
    }
}

extension MembershipGossipLogic {
    internal var nodeName: String {
        self.localNode.endpoint.systemName
    }
}
