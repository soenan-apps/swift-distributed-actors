// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
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
import XCTest

@testable import DistributedCluster

extension OpLogClusterReceptionistTests {
    internal func test_clusterReceptionist_shouldStreamAllRegisteredActorsInChunks() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.receptionist.ackPullReplicationIntervalSlow = .milliseconds(200)
        }
        first.cluster.join(endpoint: second.cluster.node.endpoint)
        try assertAssociated(first, withExactly: second.settings.bindNode)

        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "first")

        var allRefs: Set<ActorRef<String>> = []
        for index in 1...(first.settings.receptionist.syncBatchSize * 10) {
            let ref: ActorRef<String> = try first.spawn("example-\(index)", self.stopOnMessage)
            first.actorRefReceptionist.register(ref, with: key, replyTo: nil)
            _ = allRefs.insert(ref)
        }

        let firstProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(first).makeTestProbe("p1", expecting: Reception.Listing<ActorRef<String>>.self)
        let secondProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(second).makeTestProbe("p2", expecting: Reception.Listing<ActorRef<String>>.self)

        // ensure the ref is registered and known under both keys to both nodes
        first.actorRefReceptionist.subscribe(firstProbe.ref, to: key)
        second.actorRefReceptionist.subscribe(secondProbe.ref, to: key)

        try firstProbe.eventuallyExpectListing(expected: allRefs, within: .seconds(10))
        try secondProbe.eventuallyExpectListing(expected: allRefs, within: .seconds(10))
    }

    internal func test_clusterReceptionist_shouldSpreadInformationAmongManyNodes() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.receptionist.ackPullReplicationIntervalSlow = .milliseconds(200)
        }

        let third: ClusterSystem = await setUpNode("third")
        let fourth: ClusterSystem = await setUpNode("fourth")

        try await self.joinNodes(node: first, with: second)
        try await self.joinNodes(node: first, with: third)
        try await self.joinNodes(node: fourth, with: second)

        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "key")

        let ref: ActorRef<String> = try first.spawn("hi", self.stopOnMessage)
        first.actorRefReceptionist.register(ref, with: key, replyTo: nil)

        func expectListingContainsRef(on system: ClusterSystem) throws {
            let probe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
                self.testKit(system).makeTestProbe("p", expecting: Reception.Listing<ActorRef<String>>.self)
            system.actorRefReceptionist.subscribe(probe.ref, to: key)

            try probe.eventuallyExpectListing(expected: [ref], within: .seconds(3))
        }

        try expectListingContainsRef(on: first)
        try expectListingContainsRef(on: second)
        try expectListingContainsRef(on: third)
        try expectListingContainsRef(on: fourth)
    }
}
