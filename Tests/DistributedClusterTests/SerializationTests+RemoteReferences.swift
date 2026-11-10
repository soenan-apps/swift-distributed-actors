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
//

import DistributedActorsTestKit
import Foundation
import NIO
import NIOFoundationCompat
import XCTest

@testable import DistributedCluster

extension SerializationTests {
    internal func test_serialize_actorRef_inMessage_forRemoting() async throws {
        let remoteCapableSystem: ClusterSystem = await self.setUpNode("remoteCapableSystem") { settings in
            settings.enabled = true
            settings.serialization.register(HasStringRef.self)
        }

        let testKit: ActorTestKit = ActorTestKit(remoteCapableSystem)
        let probe: ActorTestProbe<String> = testKit.makeTestProbe(expecting: String.self)

        let ref: ActorRef<String> = try remoteCapableSystem.spawn(
            "hello",

            .receiveMessage { message in
                probe.tell("got:\(message)")
                return .same
            }
        )

        let hasRef: HasStringRef = HasStringRef(containedRef: ref)

        pinfo("Before serialize: \(hasRef)", file: #fileID, line: #line)

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try remoteCapableSystem.serialization.serialize(hasRef)
        }
        let serializedFormat: String = serialized.buffer.stringDebugDescription()
        pinfo("serialized ref: \(serializedFormat)", file: #fileID, line: #line)
        serializedFormat.shouldContain("sact")
        serializedFormat.shouldContain("\(remoteCapableSystem.settings.bindNode.nid)")
        serializedFormat.shouldContain(remoteCapableSystem.name)  // automatically picked up name from system
        serializedFormat.shouldContain("\(remoteCapableSystem.settings.bindHost)")
        serializedFormat.shouldContain("\(remoteCapableSystem.settings.bindPort)")

        let back: HasStringRef = try shouldNotThrow {
            try remoteCapableSystem.serialization.deserialize(as: HasStringRef.self, from: serialized)
        }
        pinfo("Deserialized again: \(back)", file: #fileID, line: #line)

        back.shouldEqual(hasRef)

        back.containedRef.tell("hello")
        try probe.expectMessage("got:hello")
    }

    internal func test_deserialize_alreadyDeadActorRef_shouldDeserializeAsDeadLetters_forSystemDefinedMessageType(
        ) throws {
        let probe: ActorTestProbe<Never> = self.testKit.makeTestProbe(expecting: Never.self)
        let stoppedRef: ActorRef<String> = try system.spawn("dead-on-arrival", .stop)
        probe.watch(stoppedRef)

        let hasRef: HasStringRef = HasStringRef(containedRef: stoppedRef)
        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(hasRef)
        }

        try probe.expectTerminated(stoppedRef)

        try self.testKit.eventually(within: .seconds(3)) {
            let back: HasStringRef = try shouldNotThrow {
                try system.serialization.deserialize(as: HasStringRef.self, from: serialized)
            }

            guard "\(back.containedRef.id)" == "/dead/user/dead-on-arrival" else {
                throw self.testKit.error("\(back.containedRef.id) is not equal to expected /dead/user/dead-on-arrival")
            }
        }
    }

    internal func test_deserialize_alreadyDeadActorRef_shouldDeserializeAsDeadLetters_forUserDefinedMessageType(
        ) throws {
        let stoppedRef: ActorRef<InterestingMessage> = try system.spawn("dead-on-arrival", .stop)  // stopped
        let hasRef: HasInterestingMessageRef = HasInterestingMessageRef(containedInterestingRef: stoppedRef)

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(hasRef)
        }

        try self.testKit.eventually(within: .seconds(3)) {
            let back: HasInterestingMessageRef = try shouldNotThrow {
                try system.serialization.deserialize(as: HasInterestingMessageRef.self, from: serialized)
            }

            back.containedInterestingRef.tell(InterestingMessage())
            guard "\(back.containedInterestingRef.id)" == "/dead/user/dead-on-arrival" else {
                throw self.testKit.error(
                    "\(back.containedInterestingRef.id) is not equal to expected /dead/user/dead-on-arrival"
                )
            }
        }
    }

    internal func test_serialize_shouldNotSerializeNotRegisteredType() throws {
        _ = try shouldThrow {
            try system.serialization.serialize(NotCodableHasInt(containedInt: 1_337))
        }
    }

    internal func test_serialize_receivesSystemMessages_inMessage() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)

        let watchMe: ActorRef<String> = try system.spawn("watchMe", .ignore)

        let ref: ActorRef<String> = try system.spawn(
            "shouldGetSystemMessage",

            .setup { context in
                context.watch(watchMe)
                return .receiveSignal { _, signal in
                    switch signal {
                    case let terminated as Signals.Terminated:
                        probe.tell("terminated:\(terminated.id.name)")

                    default:
                        ()
                    }
                    return .same
                }
            }
        )

        let sysRef: AddressableActorRef = ref.asAddressable

        let hasSysRef: HasReceivesSystemMsgs = HasReceivesSystemMsgs(sysRef: ref)

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(hasSysRef)
        }

        let back: HasReceivesSystemMsgs = try shouldNotThrow {
            try system.serialization.deserialize(as: HasReceivesSystemMsgs.self, from: serialized)
        }

        back.sysRef.id.shouldEqual(sysRef.id)

        // Only to see that the deserialized ref indeed works for sending system messages to it
        back.sysRef.sendSystemMessage(
            .terminated(ref: watchMe.asAddressable, existenceConfirmed: false),
            file: #filePath,
            line: #line
        )
        try probe.expectMessage("terminated:watchMe")
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Error envelope serialization
}
