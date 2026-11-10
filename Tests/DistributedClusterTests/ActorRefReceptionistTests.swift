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

internal final class ActorRefReceptionistTests: SingleClusterSystemXCTestCase {
    internal let receptionistBehavior: Behavior<Receptionist.Message> = OperationLogClusterReceptionist(
        settings: .default
    ).behavior

    internal func test_receptionist_shouldRespondWithRegisteredRefsForKey() throws {
        let receptionist: SystemReceptionist = SystemReceptionist(
            ref: try system.spawn(
                "test-receptionist",
                self.receptionistBehavior
            )
        )
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> = self.testKit.makeTestProbe()

        let refA: ActorRef<String> = try system.spawn(
            .anonymous,

            .receiveMessage { message in
                probe.tell("forwardedA:\(message)")
                return .same
            }
        )

        let refB: ActorRef<String> = try system.spawn(
            .anonymous,

            .receiveMessage { message in
                probe.tell("forwardedB:\(message)")
                return .same
            }
        )

        let key: Reception.Key<ActorRef<String>> = .init(ActorRef<String>.self, id: "test")

        receptionist.register(refA, with: key, replyTo: nil)
        receptionist.register(refB, with: key, replyTo: nil)
        receptionist.lookup(key, replyTo: lookupProbe.ref, timeout: .effectivelyInfinite)

        let listing: Reception.Listing<ActorRef<String>> = try lookupProbe.expectMessage()

        listing.refs.count.shouldEqual(2)
        for ref in listing.refs {
            ref.tell("test")
        }

        try probe.expectMessagesInAnyOrder(["forwardedA:test", "forwardedB:test"])
    }

    internal func test_receptionist_shouldRespondWithEmptyRefForUnknownKey() throws {
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
                .same
            }
        )

        let key: Reception.Key<ActorRef<String>> = .init(ActorRef<String>.self, id: "test")

        receptionist.register(ref, with: key, replyTo: nil)

        let unknownKey: Reception.Key<ActorRef<String>> = .init(ActorRef<String>.self, id: "unknown")
        receptionist.lookup(unknownKey, replyTo: lookupProbe.ref, timeout: .effectivelyInfinite)

        let listing: Reception.Listing<ActorRef<String>> = try lookupProbe.expectMessage()

        listing.refs.count.shouldEqual(0)
    }

    internal func test_receptionist_shouldNotRegisterTheSameRefTwice() throws {
        let receptionist: SystemReceptionist = SystemReceptionist(
            ref: try system.spawn(
                "test-receptionist",
                self.receptionistBehavior
            )
        )
        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> = self.testKit.makeTestProbe()

        let ref: ActorRef<String> = try system.spawn(.anonymous, .receiveMessage { _ in .same })

        let key: Reception.Key<ActorRef<String>> = .init(ActorRef<String>.self, id: "test")

        receptionist.register(ref, with: key, replyTo: nil)
        receptionist.register(ref, with: key, replyTo: nil)

        receptionist.lookup(key, replyTo: lookupProbe.ref, timeout: .effectivelyInfinite)

        let listing: Reception.Listing<ActorRef<String>> = try lookupProbe.expectMessage()

        listing.refs.count.shouldEqual(1)
    }

    internal func test_receptionist_shouldRemoveAndAddNewSingletonRef() throws {
        let receptionist: SystemReceptionist = SystemReceptionist(
            ref: try system.spawn(
                "test-receptionist",
                self.receptionistBehavior
            )
        )
        let lookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> = self.testKit.makeTestProbe()

        let old: ActorRef<String> = try system.spawn(
            .anonymous,

            .receive { context, _ in
                context.log.info("Stopping...")
                return .stop
            }
        )
        let new: ActorRef<String> = try system.spawn(
            .anonymous,

            .receiveMessage { _ in
                .same
            }
        )

        let key: Reception.Key<ActorRef<String>> = .init(ActorRef<String>.self, id: "shouldBeOne")

        receptionist.register(old, with: key, replyTo: nil)
        old.tell("stop")
        receptionist.register(new, with: key, replyTo: nil)

        try self.testKit.eventually(within: .seconds(2)) {
            receptionist.lookup(key, replyTo: lookupProbe.ref, timeout: .effectivelyInfinite)
            let listing: Reception.Listing<ActorRef<String>> = try lookupProbe.expectMessage()

            if listing.refs.count != 1 {
                throw Boom("Listing had more members than 1, expected 1. Listing: \(listing.refs)")
            }
        }
    }

}
