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
import NIO
import XCTest

@testable import DistributedCluster

extension MembershipGossipTests {
    internal func test_converged_shouldBeTrue_forNoMembers() {
        var gossip: Cluster.MembershipGossip = Cluster.MembershipGossip(ownerNode: self.nodeA)
        _ = gossip.membership.join(self.nodeA)
        gossip.converged().shouldBeTrue()

        gossip.incrementOwnerVersion()
        gossip.converged().shouldBeTrue()
    }

    internal func test_converged_amongUpMembers() {
        var gossip: Cluster.MembershipGossip = Cluster.MembershipGossip(ownerNode: self.nodeA)
        _ = gossip.membership.join(self.nodeA)
        _ = gossip.membership.mark(self.nodeA, as: .operational)

        _ = gossip.membership.join(self.nodeB)
        _ = gossip.membership.mark(self.nodeB, as: .operational)

        _ = gossip.membership.join(self.nodeC)
        _ = gossip.membership.mark(self.nodeC, as: .operational)

        gossip.seen.incrementVersion(owner: self.nodeA, at: self.nodeA)
        gossip.seen.incrementVersion(owner: self.nodeA, at: self.nodeB)
        gossip.seen.incrementVersion(owner: self.nodeA, at: self.nodeC)
        // we are "ahead" of others
        gossip.converged().shouldBeFalse()

        gossip.seen.incrementVersion(owner: self.nodeB, at: self.nodeA)
        gossip.seen.incrementVersion(owner: self.nodeB, at: self.nodeB)
        // others still catching up
        gossip.converged().shouldBeFalse()

        gossip.seen.incrementVersion(owner: self.nodeB, at: self.nodeC)
        // second has caught up, but third still not
        gossip.converged().shouldBeFalse()

        gossip.seen.incrementVersion(owner: self.nodeC, at: self.nodeA)
        // second has caught up, but third catching up
        gossip.converged().shouldBeFalse()

        gossip.seen.incrementVersion(owner: self.nodeC, at: self.nodeB)
        gossip.seen.incrementVersion(owner: self.nodeC, at: self.nodeC)
        // second and third have caught up
        gossip.converged().shouldBeTrue()

        // if second and third keep moving on, they still have at-least seen our version,
        // co convergence still should remain true
        gossip.seen.incrementVersion(owner: self.nodeC, at: self.nodeC)

        gossip.seen.incrementVersion(owner: self.nodeB, at: self.nodeC)
        gossip.seen.incrementVersion(owner: self.nodeB, at: self.nodeC)
        gossip.converged().shouldBeTrue()
    }

    internal func test_converged_othersAreOnlyDown() throws {
        let gossip: Cluster.MembershipGossip = try Cluster.MembershipGossip.parse(
            """
            A.up B.down
            A: A@8 B@5
            B: B@6
            C: A@7 B@5
            """,
            owner: self.nodeA,
            nodes: self.allNodes,
            file: #file,
            line: #line
        )

        // since all other nodes other than A are down or joining, thus we do not count them in convergence
        gossip.converged().shouldBeTrue()
    }

    internal func test_gossip_eventuallyConverges() throws {
        let firstGossip: Cluster.MembershipGossip = makeRandomGossip(owner: self.nodeA)
        let secondGossip: Cluster.MembershipGossip = makeRandomGossip(owner: self.nodeB)
        let thirdGossip: Cluster.MembershipGossip = makeRandomGossip(owner: self.nodeC)
        let fourthGossip: Cluster.MembershipGossip = makeRandomGossip(owner: self.fourthNode)

        var gossips: [Int: Cluster.MembershipGossip] = [
            1: firstGossip,
            2: secondGossip,
            3: thirdGossip,
            4: fourthGossip,
        ]

        for (_, gossip) in gossips {
            assert(!gossip.converged(), "Should not start out convergent")
        }

        var gossipSend: Int = 0
        let gossipSendsMax: Int = 100
        while gossipSend < gossipSendsMax {
            let (_, from): (Int, Cluster.MembershipGossip) = try XCTUnwrap(gossips.randomElement())
            var (toId, target): (Int, Cluster.MembershipGossip) = try XCTUnwrap(gossips.randomElement())

            _ = target.mergeForward(incoming: from)
            gossips[toId] = target

            if gossips.allSatisfy({ $1.converged() }) {
                break
            }

            gossipSend += 1
        }

        let allConverged: Bool = gossips.allSatisfy { $1.converged() }
        guard allConverged else {
            XCTFail(
                """
                Gossips among \(gossips.count) members did NOT converge after \(gossipSend) (individual) sends.
                \(gossips.values.map { "\($0)" }.joined(separator: "\n"))
                """
            )
            return
        }

        pinfo(
            "Gossip converged on all \(gossips.count) members, after \(gossipSend) (individual) sends",
            file: #fileID,
            line: #line
        )
    }

    private func makeRandomGossip(owner node: Cluster.Node) -> Cluster.MembershipGossip {
        var gossip: Cluster.MembershipGossip = Cluster.MembershipGossip(ownerNode: node)
        _ = gossip.membership.join(node)
        _ = gossip.membership.mark(node, as: .joining)
        var versionVector: VersionVector = VersionVector()
        versionVector.state[.node(node)] = VersionVector.Version(node.port)
        gossip.seen.underlying[node] = .init(versionVector)

        // know just enough that we're not alone and thus need to communicate:
        _ = gossip.membership.join(self.nodeA)
        _ = gossip.membership.mark(self.nodeA, as: .operational)
        _ = gossip.seen.incrementVersion(owner: self.nodeA, at: self.nodeA)
        _ = gossip.seen.incrementVersion(owner: node, at: self.nodeA)

        _ = gossip.membership.join(self.nodeB)
        _ = gossip.membership.mark(self.nodeB, as: .operational)
        _ = gossip.seen.incrementVersion(owner: self.nodeB, at: self.nodeB)
        _ = gossip.seen.incrementVersion(owner: self.nodeB, at: self.nodeB)
        _ = gossip.seen.incrementVersion(owner: node, at: self.nodeB)
        _ = gossip.seen.incrementVersion(owner: node, at: self.nodeB)
        return gossip
    }
}
