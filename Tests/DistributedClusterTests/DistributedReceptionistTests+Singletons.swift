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
    internal func test_receptionist_shouldRemoveAndAddNewSingletonRef() async throws {
        var old: Forwarder? = Forwarder(probe: nil, name: "old", actorSystem: system)
        let new: Forwarder = Forwarder(probe: nil, name: "new", actorSystem: system)

        try await system.receptionist.checkIn(XCTUnwrap(old), with: .forwarders)

        try await self.testKit.eventually(within: .seconds(2)) {
            let lookup: Set<Forwarder> = await system.receptionist.lookup(.forwarders)
            if lookup.count != 1 {
                throw try Boom("Expected lookup to contain ONLY \(XCTUnwrap(old).id), but was: \(lookup)")
            }
        }

        // release the old ref
        old = nil
        await system.receptionist.checkIn(new, with: .forwarders)

        try await self.testKit.eventually(within: .seconds(5)) {
            let lookup: Set<Forwarder> = await system.receptionist.lookup(.forwarders)
            if lookup.count != 1 {
                throw Boom("Listing had more members than 1, expected 1, was: \(lookup)")
            }
        }
    }

    //    func test_receptionist_shouldReplyWithRegistered() throws {
    //        let receptionist = SystemReceptionist(ref: try system.spawn("receptionist", self.receptionistBehavior))
    //        let probe: ActorTestProbe<Reception.Registered<ActorRef<String>>> = self.testKit.makeTestProbe()
    //
    //        let key = DistributedReception.Key(ActorRef<String>.self, id: "test")
    //
    //        receptionist.checkIn(ref, with: key, replyTo: probe.ref)
    //
    //        let checkedIn = try probe.expectMessage()
    //
    //        checkedIn.key.id.shouldEqual(key.id)
    //        checkedIn.ref.shouldEqual(ref)
    //    }
    //
    //    func test_receptionist_shouldCheckOutTerminatedRefs() throws {
    //        let receptionist = SystemReceptionist(ref: try system.spawn("receptionist", self.receptionistBehavior))
    //        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> = self.testKit.makeTestProbe()
    //
    //        let ref: ActorRef<String> = try system.spawn(
    //                .anonymous,
    //                .receiveMessage { _ in
    //                    .stop
    //                }
    //        )
    //
    //        let key = Reception.Key(ActorRef<String>.self, id: "test")
    //
    //        receptionist.checkIn(ref, with: key)
    //
    //        ref.tell("stop")
    //
    //        try self.testKit.eventually(within: .seconds(1)) {
    //            receptionist.lookup(key, replyTo: lookupProbe.ref)
    //            let message = try lookupProbe.expectMessage()
    //
    //            // modify TestKit to allow usage of matchers instead
    //            guard message.refs.isEmpty else {
    //                throw self.testKit.error()
    //            }
    //        }
    //    }
    //
    //    func test_receptionist_shouldContinuouslySendUpdatesForSubscriptions() throws {
    //        let receptionist = SystemReceptionist(ref: try system.spawn("receptionist", self.receptionistBehavior))
    //        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> = self.testKit.makeTestProbe()
    //
    //        let refA: ActorRef<String> = try system.spawn(
    //                .anonymous,
    //                .receiveMessage { _ in
    //                    .same
    //                }
    //        )
    //
    //        let refB: ActorRef<String> = try system.spawn(
    //                .anonymous,
    //                .receiveMessage { _ in
    //                    .stop
    //                }
    //        )
    //
    //        let key = Reception.Key(ActorRef<String>.self, id: "test")
    //
    //        receptionist.listing(lookupProbe.ref, to: key)
    //        try lookupProbe.expectMessage(Reception.Listing(refs: [], key: key))
    //
    //        receptionist.checkIn(refA, with: key)
    //        try lookupProbe.expectMessage(Reception.Listing(refs: [refA.asAddressable], key: key))
    //
    //        receptionist.checkIn(refB, with: key)
    //        try lookupProbe.expectMessage(Reception.Listing(refs: [refA.asAddressable, refB.asAddressable], key: key))
    //
    //        refB.tell("stop")
    //        try lookupProbe.expectMessage(Reception.Listing(refs: [refA.asAddressable], key: key))
    //    }
    //
    // // ====
    // ------------------------------------------------------------------------------------------------------------
    //    // MARK: Delayed flush
    //
    //    func test_delayedFlush_shouldEmitEvenWhenAllPeersRemoved() throws {
    //        let receptionist = SystemReceptionist(ref: try system.spawn("receptionist", self.receptionistBehavior))
    //        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> = self.testKit.makeTestProbe()
    //
    //        let key = Reception.Key(ActorRef<String>.self, id: "test")
    //
    //        receptionist.listing(lookupProbe.ref, to: key)
    //        _ = try lookupProbe.expectMessage()
    //
    //        receptionist.checkIn(try system.spawn(.anonymous, .receiveMessage { _ in .same }), with: key)
    //        receptionist.checkIn(try system.spawn(.anonymous, .receiveMessage { _ in .same }), with: key)
    //        receptionist.checkIn(try system.spawn(.anonymous, .receiveMessage { _ in .same }), with: key)
    //
    //        // we're expecting to get the update in batch, thanks to the delayed flushing
    //        let listing1 = try lookupProbe.expectMessage()
    //        listing1.count.shouldEqual(3)
    //    }
}
