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

import Distributed
import DistributedActorsTestKit
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

extension DistributedReceptionistTests {
    internal func test_receptionist_listing_shouldRespondWithRegisteredRefsForKey() async throws {
        let receptionist: OpLogDistributedReceptionist = system.receptionist
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let forwarderA: Forwarder = Forwarder(probe: probe, name: "A", actorSystem: system)
        let forwarderB: Forwarder = Forwarder(probe: probe, name: "B", actorSystem: system)

        system.log.notice("Checking in: \(forwarderA.id)")
        await receptionist.checkIn(forwarderA, with: .forwarders)
        system.log.notice("Checking in: \(forwarderB.id)")
        await receptionist.checkIn(forwarderB, with: .forwarders)

        var index: Int = 0
        system.log.notice("here")
        for await forwarder in receptionist.listing(of: .forwarders) {
            system.log.notice("here more \(index): \(forwarder.id)")
            index += 1
            try await forwarder.forward(message: "test")

            if index == 2 {
                break
            }
        }

        try probe.expectMessagesInAnyOrder(
            [
                "\(forwarderA.id) A forwarded: test",
                "\(forwarderB.id) B forwarded: test",
            ]
        )
    }

    internal func test_receptionist_listing_shouldEndAfterTaskIsCancelled() async throws {
        let receptionist: OpLogDistributedReceptionist = self.system.receptionist
        let probeA: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let probeB: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let bossA: Boss = Boss(probe: probeA, name: "A", actorSystem: self.system)
        let bossB: Boss = Boss(probe: probeB, name: "B", actorSystem: self.system)

        let workerA: Worker = Worker(name: "A", actorSystem: self.system)
        let workerB: Worker = Worker(name: "B", actorSystem: self.system)
        let workerC: Worker = Worker(name: "C", actorSystem: self.system)

        try await bossA.findWorkers()
        try await bossB.findWorkers()

        await receptionist.checkIn(workerA, with: .workers)

        try probeA.expectMessage("\(bossA.id) A found \(workerA.id)")
        try probeB.expectMessage("\(bossB.id) B found \(workerA.id)")

        try await bossB.done()
        try probeB.expectMessage("B done")

        await receptionist.checkIn(workerB, with: .workers)

        try probeA.expectMessage("\(bossA.id) A found \(workerB.id)")
        try probeB.expectNoMessage(for: .milliseconds(500))

        try await bossA.done()
        try probeA.expectMessage("A done")

        await receptionist.checkIn(workerC, with: .workers)

        try probeA.expectNoMessage(for: .milliseconds(500))
        try probeB.expectNoMessage(for: .milliseconds(500))
    }

    internal func test_receptionist_shouldRespondWithEmptyRefForUnknownKey() throws {
        runAsyncAndBlock {
            let receptionist: OpLogDistributedReceptionist = system.receptionist

            let ref: Forwarder = Forwarder(probe: nil, name: "C", actorSystem: system)
            await receptionist.checkIn(ref, with: .forwarders)

            let listing: Set<Forwarder> = await receptionist.lookup(.unknown)
            listing.count.shouldEqual(0)
        }
    }

    // ====
    // ----------------------------------------------------------------------------------------------------------------

    internal func test_receptionist_shouldNotRegisterTheSameRefTwice() async {
        let ref: Forwarder = Forwarder(probe: nil, name: "D", actorSystem: system)

        await system.receptionist.checkIn(ref, with: .forwarders)
        await system.receptionist.checkIn(ref, with: .forwarders)

        let listing: Set<Forwarder> = await system.receptionist.lookup(.forwarders)

        listing.count.shouldEqual(1)
    }

    internal func test_receptionist_happyPath_lookup_only() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await self.setUpPair { settings in
            settings.enabled = true
        }

        let ref: Forwarder = Forwarder(probe: nil, name: "D", actorSystem: first)
        await first.receptionist.checkIn(ref, with: .forwarders)

        first.cluster.join(endpoint: second.cluster.node.endpoint)
        try await first.cluster.joined(node: second.cluster.node, within: .seconds(30))

        try await testKit.eventually(within: .seconds(5)) {
            let lookup: Set<Forwarder> = await second.receptionist.lookup(.forwarders)
            guard let registeredActor = lookup.first, lookup.count == 1 else {
                throw TestError("Lookup returned but is empty: \(lookup)")
            }
            registeredActor.id.shouldEqual(ref.id)
        }
    }

    internal func test_receptionist_happyPath_lookup_then_listing() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await self.setUpPair { settings in
            settings.enabled = true
        }

        let ref: Forwarder = Forwarder(probe: nil, name: "D", actorSystem: first)
        await first.receptionist.checkIn(ref, with: .forwarders)

        first.cluster.join(endpoint: second.cluster.node.endpoint)
        try await first.cluster.joined(node: second.cluster.node, within: .seconds(30))

        try await testKit.eventually(within: .seconds(5)) {
            let lookup: Set<Forwarder> = await second.receptionist.lookup(.forwarders)
            guard let registeredActor = lookup.first, lookup.count == 1 else {
                throw TestError("Lookup returned but is empty: \(lookup)")
            }
            registeredActor.id.shouldEqual(ref.id)

            let listing: DistributedReception.GuestListing<Forwarder> = second.receptionist.listing(
                of: .forwarders
            )
            for await forwarder in listing {
                forwarder.id.shouldEqual(ref.id)
                return
            }
        }
    }
}
