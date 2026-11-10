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

import DistributedActorsTestKit
import Foundation
import NIO
import NIOFoundationCompat
import XCTest

@testable import DistributedCluster

extension SerializationPoolTests {
    internal func test_serializationPool_shouldSerializeMessagesInDifferentNonDefaultGroupsInParallel() throws {
        let actorSystem: ClusterSystem = try XCTUnwrap(self.system)
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        let firstActorPath: ActorPath = try XCTUnwrap(self.actorPath1)
        let secondActorPath: ActorPath = try XCTUnwrap(self.actorPath2)
        let activeEventLoop: EventLoop = try XCTUnwrap(self.eventLoop)
        let serializationPool: SerializationPool = try SerializationPool(
            settings: SerializationPoolSettings(
                serializationGroups: [[firstActorPath], [secondActorPath]]
            ),
            serialization: actorSystem.serialization
        )
        defer { serializationPool.shutdown() }

        let probe: ActorTestProbe<String> = kit.makeTestProbe()

        // We are locking here to validate that the objects are being serialized
        // on different, separate threads, because only then will we receive
        // the "p2" message when unlocking `test2.lock` and afterwards "p1"
        // when unlocking `test1.lock`
        let test1: SerializationPoolFirstPayload = SerializationPoolFirstPayload()
        test1.lock.lock()
        let promise1: EventLoopPromise<Serialization.Serialized> = activeEventLoop.makePromise()
        promise1.futureResult.whenSuccess { _ in
            probe.tell("p1")
        }

        let test2: SerializationPoolFirstPayload = SerializationPoolFirstPayload()
        test2.lock.lock()
        let promise2: EventLoopPromise<Serialization.Serialized> = activeEventLoop.makePromise()
        promise2.futureResult.whenSuccess { _ in
            probe.tell("p2")
        }

        serializationPool.serialize(message: test1, recipientPath: firstActorPath, promise: promise1)
        serializationPool.serialize(message: test2, recipientPath: secondActorPath, promise: promise2)

        test2.lock.unlock()
        try probe.expectMessage("p2")

        test1.lock.unlock()
        try probe.expectMessage("p1")
    }

}
