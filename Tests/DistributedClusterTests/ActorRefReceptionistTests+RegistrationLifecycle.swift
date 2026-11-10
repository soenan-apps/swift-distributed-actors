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

import Distributed
import DistributedActorsTestKit
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

extension ActorRefReceptionistTests {
    internal func test_receptionist_shouldReplyWithRegistered() throws {
        let receptionist: SystemReceptionist = SystemReceptionist(
            ref: try system.spawn(
                "test-receptionist",
                self.receptionistBehavior
            )
        )
        let probe: ActorTestProbe<Reception.Registered<ActorRef<String>>> = self.testKit.makeTestProbe()

        let ref: ActorRef<String> = try system.spawn(
            .anonymous,

            .receiveMessage { _ in
                .same
            }
        )

        let key: Reception.Key<ActorRef<String>> = .init(ActorRef<String>.self, id: "test")

        receptionist.register(ref, with: key, replyTo: probe.ref)

        let registered: Reception.Registered<ActorRef<String>> = try probe.expectMessage()

        registered.key.id.shouldEqual(key.id)
        registered.ref.shouldEqual(ref)
    }

    internal func test_receptionist_shouldUnregisterTerminatedRefs() throws {
        let receptionist: SystemReceptionist = SystemReceptionist(
            ref: try system.spawn(
                "test-receptionist",
                self.receptionistBehavior
            )
        )
        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> = self.testKit.makeTestProbe()

        let ref: ActorRef<String> = try system.spawn(
            .anonymous,

            .receiveMessage { _ in
                .stop
            }
        )

        let key: Reception.Key<ActorRef<String>> = .init(ActorRef<String>.self, id: "test")

        receptionist.register(ref, with: key, replyTo: nil)

        ref.tell("stop")

        try self.testKit.eventually(within: .seconds(1)) {
            receptionist.lookup(key, replyTo: lookupProbe.ref, timeout: .effectivelyInfinite)
            let message: Reception.Listing<ActorRef<String>> = try lookupProbe.expectMessage()

            // modify TestKit to allow usage of matchers instead
            guard message.refs.isEmpty else {
                throw self.testKit.error()
            }
        }
    }

    internal func test_receptionist_shouldContinuouslySendUpdatesForSubscriptions() throws {
        let receptionist: SystemReceptionist = SystemReceptionist(
            ref: try system.spawn(
                "test-receptionist",
                self.receptionistBehavior
            )
        )
        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> = self.testKit.makeTestProbe()

        let refA: ActorRef<String> = try system.spawn(
            .anonymous,

            .receiveMessage { _ in
                .same
            }
        )

        let refB: ActorRef<String> = try system.spawn(
            .anonymous,

            .receiveMessage { _ in
                .stop
            }
        )

        let key: Reception.Key<ActorRef<String>> = .init(ActorRef<String>.self, id: "test")

        receptionist.subscribe(lookupProbe.ref, to: key)
        try lookupProbe.expectMessage(Reception.Listing(refs: [], key: key))

        receptionist.register(refA, with: key, replyTo: nil)
        try lookupProbe.expectMessage(Reception.Listing(refs: [refA.asAddressable], key: key))

        receptionist.register(refB, with: key, replyTo: nil)
        try lookupProbe.expectMessage(Reception.Listing(refs: [refA.asAddressable, refB.asAddressable], key: key))

        refB.tell("stop")
        try lookupProbe.expectMessage(Reception.Listing(refs: [refA.asAddressable], key: key))
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Delayed flush

    internal func test_delayedFlush_shouldEmitEvenWhenAllPeersRemoved() throws {
        let receptionist: SystemReceptionist = SystemReceptionist(
            ref: try system.spawn(
                "test-receptionist",
                self.receptionistBehavior
            )
        )
        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> = self.testKit.makeTestProbe()

        let key: Reception.Key<ActorRef<String>> = .init(ActorRef<String>.self, id: "test")

        receptionist.subscribe(lookupProbe.ref, to: key)
        _ = try lookupProbe.expectMessage()

        receptionist.register(try system.spawn(.anonymous, .receiveMessage { _ in .same }), with: key, replyTo: nil)
        receptionist.register(try system.spawn(.anonymous, .receiveMessage { _ in .same }), with: key, replyTo: nil)
        receptionist.register(try system.spawn(.anonymous, .receiveMessage { _ in .same }), with: key, replyTo: nil)

        // we're expecting to get the update in batch, thanks to the delayed flushing
        let listing1: Reception.Listing<ActorRef<String>> = try lookupProbe.expectMessage()
        listing1.count.shouldEqual(3)
    }
}
