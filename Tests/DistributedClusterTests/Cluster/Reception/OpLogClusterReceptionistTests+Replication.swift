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
    internal func test_shouldReplicateRegistrations() async throws {
        let (local, remote): (ClusterSystem, ClusterSystem) = await setUpPair()
        let testKit: ActorTestKit = self.testKit(local)
        try await self.joinNodes(node: local, with: remote)

        let probe: ActorTestProbe<String> = testKit.makeTestProbe(expecting: String.self)
        let registeredProbe: ActorTestProbe<Reception.Registered<ActorRef<String>>> =
            testKit.makeTestProbe("registered", expecting: Reception.Registered<ActorRef<String>>.self)

        let ref: ActorRef<String> = try local.spawn(
            .anonymous,
            .receiveMessage { message in
                probe.tell("received:\(message)")
                return .same
            }
        )

        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "test")

        // subscribe on `remote`
        let subscriberProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            testKit.makeTestProbe(expecting: Reception.Listing<ActorRef<String>>.self)
        remote.actorRefReceptionist.subscribe(subscriberProbe.ref, to: key)
        _ = try subscriberProbe.expectMessage()

        // register on `local`
        local.actorRefReceptionist.register(ref, with: key, replyTo: registeredProbe.ref)
        _ = try registeredProbe.expectMessage()

        let listing: Reception.Listing<ActorRef<String>> = try subscriberProbe.expectMessage()
        listing.refs.count.shouldEqual(1)
        guard let registeredRef = listing.refs.first else {
            throw subscriberProbe.error("listing contained no entries, expected 1")
        }
        registeredRef.tell("test")

        try probe.expectMessage("received:test")
    }

    internal func test_shouldSyncPeriodically() async throws {
        let (local, remote): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.receptionist.ackPullReplicationIntervalSlow = .seconds(1)
        }

        let probe: ActorTestProbe<String> = self.testKit(local).makeTestProbe(expecting: String.self)
        let registeredProbe: ActorTestProbe<Reception.Registered<ActorRef<String>>> =
            self.testKit(local).makeTestProbe(expecting: Reception.Registered<ActorRef<String>>.self)
        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(local).makeTestProbe(expecting: Reception.Listing<ActorRef<String>>.self)

        let ref: ActorRef<String> = try local.spawn(
            .anonymous,
            .receiveMessage { message in
                probe.tell("received:\(message)")
                return .same
            }
        )

        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "test")

        remote.actorRefReceptionist.subscribe(lookupProbe.ref, to: key)

        _ = try lookupProbe.expectMessage()

        local.actorRefReceptionist.register(ref, with: key, replyTo: registeredProbe.ref)
        _ = try registeredProbe.expectMessage()

        local.cluster.join(endpoint: remote.cluster.node.endpoint)
        try assertAssociated(local, withExactly: remote.settings.bindNode)

        let listing: Reception.Listing<ActorRef<String>> = try lookupProbe.expectMessage()
        listing.refs.count.shouldEqual(1)
        guard let registeredRef = listing.refs.first else {
            throw lookupProbe.error("listing contained no entries, expected 1")
        }
        registeredRef.tell("test")

        try probe.expectMessage("received:test")
    }

    internal func test_shouldMergeEntriesOnSync() async throws {
        let (local, remote): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.receptionist.ackPullReplicationIntervalSlow = .seconds(1)
        }

        let registeredProbe: ActorTestProbe<Reception.Registered<ActorRef<String>>> =
            self.testKit(local).makeTestProbe("registeredProbe", expecting: Reception.Registered<ActorRef<String>>.self)
        let localLookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(local).makeTestProbe("localLookupProbe", expecting: Reception.Listing<ActorRef<String>>.self)
        let remoteLookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(remote).makeTestProbe("remoteLookupProbe", expecting: Reception.Listing<ActorRef<String>>.self)

        let behavior: Behavior<String> = .receiveMessage { _ in
            .same
        }

        let refA: ActorRef<String> = try local.spawn("refA", behavior)
        let refB: ActorRef<String> = try local.spawn("refB", behavior)
        let refC: ActorRef<String> = try remote.spawn("refC", behavior)
        let refD: ActorRef<String> = try remote.spawn("refD", behavior)

        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "test")

        local.actorRefReceptionist.register(refA, with: key, replyTo: registeredProbe.ref)
        _ = try registeredProbe.expectMessage()

        local.actorRefReceptionist.register(refB, with: key, replyTo: registeredProbe.ref)
        _ = try registeredProbe.expectMessage()

        remote.actorRefReceptionist.register(refC, with: key, replyTo: registeredProbe.ref)
        _ = try registeredProbe.expectMessage()

        remote.actorRefReceptionist.register(refD, with: key, replyTo: registeredProbe.ref)
        _ = try registeredProbe.expectMessage()

        local.actorRefReceptionist.subscribe(localLookupProbe.ref, to: key)
        _ = try localLookupProbe.expectMessage()

        remote.actorRefReceptionist.subscribe(remoteLookupProbe.ref, to: key)
        _ = try remoteLookupProbe.expectMessage()

        local.cluster.join(endpoint: remote.cluster.node.endpoint)
        try assertAssociated(local, withExactly: remote.settings.bindNode)

        let localListing: Reception.Listing<ActorRef<String>> = try localLookupProbe.expectMessage()
        localListing.refs.count.shouldEqual(4)

        let remoteListing: Reception.Listing<ActorRef<String>> = try remoteLookupProbe.expectMessage()
        remoteListing.refs.count.shouldEqual(4)
    }
}
