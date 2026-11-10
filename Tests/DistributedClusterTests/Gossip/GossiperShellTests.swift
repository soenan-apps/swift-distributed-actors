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
import Foundation
import NIOSSL
import XCTest

@testable import DistributedCluster

internal final class GossiperShellTests: SingleClusterSystemXCTestCase {
    internal func peerBehavior<T: Codable>() -> Behavior<GossipShell<T, String>.Message> {
        .receiveMessage { msg in
            if "\(msg)".contains("stop") {
                return .stop
            }
            return .same
        }
    }

    // MARK: test_down_beGossipedToOtherNodes

    internal func test_down_beGossipedToOtherNodes() throws {
        let probeForTest: ActorTestProbe<[AddressableActorRef]> =
            self.testKit.makeTestProbe(expecting: [AddressableActorRef].self)

        let control: GossiperControl<InspectOfferedPeersTestGossipLogic.Gossip, String> = try Gossiper.spawn(
            self.system,
            name: "gossiper",
            settings: .init(
                interval: .seconds(1),
                style: .unidirectional
            )
        ) { _ in InspectOfferedPeersTestGossipLogic(offeredPeersProbe: probeForTest.ref) }

        let first: ActorRef<GossipShell<InspectOfferedPeersTestGossipLogic.Gossip, String>.Message> =
            try self.system.spawn("first", self.peerBehavior())
        let second: ActorRef<GossipShell<InspectOfferedPeersTestGossipLogic.Gossip, String>.Message> =
            try self.system.spawn("second", self.peerBehavior())

        control.introduce(peer: first)
        control.introduce(peer: second)
        control.update(StringGossipIdentifier("hi"), payload: .init("hello"))

        try Set(probeForTest.expectMessage()).shouldEqual(Set([first.asAddressable, second.asAddressable]))

        first.tell(.removePayload(identifier: StringGossipIdentifier("stop")))
        try Set(probeForTest.expectMessage()).shouldEqual(Set([second.asAddressable]))

        first.tell(.removePayload(identifier: StringGossipIdentifier("stop")))
        try probeForTest.expectNoMessage(for: .milliseconds(300))
    }

    // MARK: test_unidirectional_yetEmitsAck_shouldWarn

    internal func test_unidirectional_yetReceivesAckRef_shouldWarn() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)

        let control: GossiperControl<NoAcksTestGossipLogic.Gossip, String> = try Gossiper.spawn(
            self.system,
            name: "noAcks",
            settings: .init(
                interval: .milliseconds(100),
                style: .unidirectional
            )
        ) { _ in NoAcksTestGossipLogic(probe: probeForTest.ref) }

        let first: ActorRef<GossipShell<GossiperTestPayload, String>.Message> =
            try self.system.spawn("first", self.peerBehavior())

        control.introduce(peer: first)
        control.update(StringGossipIdentifier("hi"), payload: .init("hello"))
        control.ref.tell(
            .gossip(
                identity: StringGossipIdentifier("example"),
                origin: first,
                .init("unexpected"),
                ackRef: system.deadLetters.adapted()  // An ACK ref is invalid for a unidirectional gossiper.
            )
        )

        try self.logCapture.awaitLogContaining(
            self.testKit,
            text: " Incoming gossip has acknowledgement actor ref and seems to be expecting an ACK, "
                + "while this gossiper is configured as .unidirectional!"
        )
    }

}
