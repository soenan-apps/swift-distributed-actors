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
    internal func test_clusterReceptionist_shouldRemoveRemoteRefs_whenTheyStop() async throws {
        try await self.shared_clusterReceptionist_shouldRemoveRemoteRefsStop(killActors: .sendStop)
    }

    internal func test_clusterReceptionist_shouldRemoveRemoteRefs_whenNodeDies() async throws {
        try await self.shared_clusterReceptionist_shouldRemoveRemoteRefsStop(killActors: .shutdownNode)
    }

    internal func test_terminatedActor_isRemovedFromAllListings() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.receptionist.ackPullReplicationIntervalSlow = .milliseconds(200)
        }
        first.cluster.join(endpoint: second.cluster.node.endpoint)
        try assertAssociated(first, withExactly: second.settings.bindNode)

        let firstKey: Reception.Key = Reception.Key(ActorRef<String>.self, id: "first")
        let extraKey: Reception.Key = Reception.Key(ActorRef<String>.self, id: "extra")

        let ref: ActorRef<String> = try first.spawn("hi", self.stopOnMessage)
        first.actorRefReceptionist.register(ref, with: firstKey, replyTo: nil)
        first.actorRefReceptionist.register(ref, with: extraKey, replyTo: nil)

        let p1f: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(first).makeTestProbe("p1f", expecting: Reception.Listing<ActorRef<String>>.self)
        let p1e: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(first).makeTestProbe("p1e", expecting: Reception.Listing<ActorRef<String>>.self)
        let p2f: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(second).makeTestProbe("p2f", expecting: Reception.Listing<ActorRef<String>>.self)
        let p2e: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(second).makeTestProbe("p2e", expecting: Reception.Listing<ActorRef<String>>.self)

        // ensure the ref is registered and known under both keys to both nodes
        first.actorRefReceptionist.subscribe(p1f.ref, to: firstKey)
        first.actorRefReceptionist.subscribe(p1e.ref, to: extraKey)

        second.actorRefReceptionist.subscribe(p2f.ref, to: firstKey)
        second.actorRefReceptionist.subscribe(p2e.ref, to: extraKey)

        func expectListingOnAllProbes(expected: Set<ActorRef<String>>) throws {
            try p1f.eventuallyExpectListing(expected: expected, within: .seconds(3))
            try p1e.eventuallyExpectListing(expected: expected, within: .seconds(3))

            try p2f.eventuallyExpectListing(expected: expected, within: .seconds(3))
            try p2e.eventuallyExpectListing(expected: expected, within: .seconds(3))
        }

        try expectListingOnAllProbes(expected: [ref])

        // terminate it
        ref.tell("stop!")

        // it should be removed from all listings; on both nodes, for all keys
        try expectListingOnAllProbes(expected: [])
    }

    internal func test_clusterReceptionist_shouldRemoveActorsOfTerminatedNodeFromListings_onNodeCrash() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.receptionist.ackPullReplicationIntervalSlow = .milliseconds(200)
        }
        first.cluster.join(endpoint: second.cluster.node.endpoint)
        try assertAssociated(first, withExactly: second.settings.bindNode)

        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "key")

        let firstRef: ActorRef<String> = try first.spawn("onFirst", self.stopOnMessage)
        first.actorRefReceptionist.register(firstRef, with: key, replyTo: nil)

        let secondRef: ActorRef<String> = try second.spawn("onSecond", self.stopOnMessage)
        second.actorRefReceptionist.register(secondRef, with: key, replyTo: nil)

        let firstProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(first).makeTestProbe("p1", expecting: Reception.Listing<ActorRef<String>>.self)
        let secondProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(second).makeTestProbe("p2", expecting: Reception.Listing<ActorRef<String>>.self)

        // ensure the ref is registered and known under both keys to both nodes
        first.actorRefReceptionist.subscribe(firstProbe.ref, to: key)
        second.actorRefReceptionist.subscribe(secondProbe.ref, to: key)

        try firstProbe.eventuallyExpectListing(expected: [firstRef, secondRef], within: .seconds(3))
        try secondProbe.eventuallyExpectListing(expected: [firstRef, secondRef], within: .seconds(3))

        // crash the second node
        try await second.shutdown().wait()

        // it should be removed from all listings; on both nodes, for all keys
        try firstProbe.eventuallyExpectListing(expected: [firstRef], within: .seconds(5))
    }

    internal func test_clusterReceptionist_shouldRemoveManyRemoteActorsFromListingInBulk() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.receptionist.ackPullReplicationIntervalSlow = .milliseconds(200)
        }
        first.cluster.join(endpoint: second.cluster.node.endpoint)
        try assertAssociated(first, withExactly: second.settings.bindNode)

        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "key")

        let firstRef: ActorRef<String> = try first.spawn("onFirst", self.stopOnMessage)
        first.actorRefReceptionist.register(firstRef, with: key, replyTo: nil)

        let remotes: [ActorRef<String>] = try (1...100).map { index in
            let ref: ActorRef<String> = try second.spawn("remote-\(index)", self.stopOnMessage)
            second.actorRefReceptionist.register(ref, with: key, replyTo: nil)
            return ref
        }

        let firstProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(first).makeTestProbe("p1", expecting: Reception.Listing<ActorRef<String>>.self)
        let secondProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(second).makeTestProbe("p2", expecting: Reception.Listing<ActorRef<String>>.self)

        // ensure the ref is registered and known under both keys to both nodes
        first.actorRefReceptionist.subscribe(firstProbe.ref, to: key)
        second.actorRefReceptionist.subscribe(secondProbe.ref, to: key)

        var allRefs: Set = Set(remotes)
        allRefs.insert(firstRef)
        try firstProbe.eventuallyExpectListing(expected: allRefs, within: .seconds(5))
        try secondProbe.eventuallyExpectListing(expected: allRefs, within: .seconds(5))

        // crash the second node
        try await second.shutdown().wait()

        // it should be removed from all listings; on both nodes, for all keys
        try firstProbe.eventuallyExpectListing(expected: [firstRef], within: .seconds(5), verbose: false)
    }
}
