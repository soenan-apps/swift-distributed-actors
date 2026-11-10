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
    internal func test_serializationPool_shouldDeserializeMessagesInDefaultGroupOnCallingThread() throws {
        let actorSystem: ClusterSystem = try XCTUnwrap(self.system)
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        let firstActorPath: ActorPath = try XCTUnwrap(self.actorPath1)
        let secondActorPath: ActorPath = try XCTUnwrap(self.actorPath2)
        let activeEventLoop: EventLoop = try XCTUnwrap(self.eventLoop)
        let serializationPool: SerializationPool = try SerializationPool(
            settings: .default,
            serialization: actorSystem.serialization
        )
        defer { serializationPool.shutdown() }
        let probe: ActorTestProbe<String> = kit.makeTestProbe()
        let json: String = "{}"

        // We are locking here to validate that the object is being deserialized
        // on the calling thread, because only then will it be able to reenter
        // the lock and return before `unlock` is called at the end of this
        // function
        SerializationPoolFirstPayload.deserializerLock.lock()
        defer { SerializationPoolFirstPayload.deserializerLock.unlock() }

        var buffer1: ByteBuffer = self.allocator.buffer(capacity: json.count)
        buffer1.writeString(json)
        let promise1: EventLoopPromise<SerializationPoolFirstPayload> = activeEventLoop.makePromise()
        promise1.futureResult.whenSuccess { _ in
            probe.tell("p1")
        }
        promise1.futureResult.whenFailure { print("\($0)") }

        SerializationPoolSecondPayload.deserializerLock.lock()
        defer { SerializationPoolSecondPayload.deserializerLock.unlock() }

        var buffer2: ByteBuffer = self.allocator.buffer(capacity: json.count)
        buffer2.writeString(json)
        let promise2: EventLoopPromise<SerializationPoolSecondPayload> = activeEventLoop.makePromise()
        promise2.futureResult.whenSuccess { _ in
            probe.tell("p2")
        }

        serializationPool.deserializeAny(
            from: .nioByteBuffer(buffer1),
            using: self.manifest1,
            recipientPath: firstActorPath,
            callback: self.completePromise(SerializationPoolFirstPayload.self, promise1)
        )
        try probe.expectMessage("p1")
        serializationPool.deserializeAny(
            from: .nioByteBuffer(buffer2),
            using: self.manifest2,
            recipientPath: secondActorPath,
            callback: self.completePromise(
                SerializationPoolSecondPayload.self,
                promise2
            )
        )
        try probe.expectMessage("p2")
    }

    internal func test_serializationPool_shouldDeserializeMessagesInTheSameNonDefaultGroupInSequence() throws {
        let actorSystem: ClusterSystem = try XCTUnwrap(self.system)
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        let firstActorPath: ActorPath = try XCTUnwrap(self.actorPath1)
        let secondActorPath: ActorPath = try XCTUnwrap(self.actorPath2)
        let activeEventLoop: EventLoop = try XCTUnwrap(self.eventLoop)
        let serializationPool: SerializationPool = try SerializationPool(
            settings: SerializationPoolSettings(
                serializationGroups: [[firstActorPath, secondActorPath]]
            ),
            serialization: actorSystem.serialization
        )
        defer { serializationPool.shutdown() }
        let probe: ActorTestProbe<String> = kit.makeTestProbe()
        let json: String = "{}"

        // We are locking here to validate that the objects are being deserialized
        // on the same, separate thread, because only then will we not receive
        // the "p2" message when unlocking `Test2.deserializationLock`, because
        // it will still wait on the `Test1.deserializerLock`
        SerializationPoolFirstPayload.deserializerLock.lock()

        var buffer1: ByteBuffer = self.allocator.buffer(capacity: json.count)
        buffer1.writeString(json)
        let promise1: EventLoopPromise<SerializationPoolFirstPayload> = activeEventLoop.makePromise()
        promise1.futureResult.whenSuccess { _ in
            probe.tell("p1")
        }
        promise1.futureResult.whenFailure { print("\($0)") }

        SerializationPoolSecondPayload.deserializerLock.lock()

        var buffer2: ByteBuffer = self.allocator.buffer(capacity: json.count)
        buffer2.writeString(json)
        let promise2: EventLoopPromise<SerializationPoolSecondPayload> = activeEventLoop.makePromise()
        promise2.futureResult.whenSuccess { _ in
            probe.tell("p2")
        }

        serializationPool.deserializeAny(
            from: .nioByteBuffer(buffer1),
            using: self.manifest1,
            recipientPath: firstActorPath,
            callback: self.completePromise(SerializationPoolFirstPayload.self, promise1)
        )
        serializationPool.deserializeAny(
            from: .nioByteBuffer(buffer2),
            using: self.manifest2,
            recipientPath: secondActorPath,
            callback: self.completePromise(
                SerializationPoolSecondPayload.self,
                promise2
            )
        )

        SerializationPoolSecondPayload.deserializerLock.unlock()

        try probe.expectNoMessage(for: .milliseconds(20))

        SerializationPoolFirstPayload.deserializerLock.unlock()
        try probe.expectMessage("p1")
        try probe.expectMessage("p2")
    }

    internal func test_serializationPool_shouldDeserializeMessagesInDifferentNonDefaultGroupsInParallel() throws {
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

        // We are locking here to validate that the objects are being deserialized
        // on different, separate threads, because only then will we receive
        // the "p2" message when unlocking `Test2.deserializerLock` and
        // afterwards "p1" when unlocking `Test1.deserializerLock`
        SerializationPoolFirstPayload.deserializerLock.lock()
        let json: String = "{}"

        var buffer1: ByteBuffer = self.allocator.buffer(capacity: json.count)
        buffer1.writeString(json)
        let promise1: EventLoopPromise<SerializationPoolFirstPayload> = activeEventLoop.makePromise()
        promise1.futureResult.whenSuccess { _ in
            probe.tell("p1")
        }
        promise1.futureResult.whenFailure { print("\($0)") }

        SerializationPoolSecondPayload.deserializerLock.lock()
        var buffer2: ByteBuffer = self.allocator.buffer(capacity: json.count)
        buffer2.writeString(json)
        let promise2: EventLoopPromise<SerializationPoolSecondPayload> = activeEventLoop.makePromise()
        promise2.futureResult.whenSuccess { _ in
            probe.tell("p2")
        }
        serializationPool.deserializeAny(
            from: .nioByteBuffer(buffer1),
            using: self.manifest1,
            recipientPath: firstActorPath,
            callback: self.completePromise(SerializationPoolFirstPayload.self, promise1)
        )
        serializationPool.deserializeAny(
            from: .nioByteBuffer(buffer2),
            using: self.manifest2,
            recipientPath: secondActorPath,
            callback: self.completePromise(
                SerializationPoolSecondPayload.self,
                promise2
            )
        )

        SerializationPoolSecondPayload.deserializerLock.unlock()
        try probe.expectMessage("p2")

        SerializationPoolFirstPayload.deserializerLock.unlock()
        try probe.expectMessage("p1")
    }

    internal func test_serializationPool_shouldExecuteSerializationAndDeserializationGroupsOnSeparateWorkerPools(
        ) throws {
        let actorSystem: ClusterSystem = try XCTUnwrap(self.system)
        let kit: ActorTestKit = try XCTUnwrap(self.testKit)
        let firstActorPath: ActorPath = try XCTUnwrap(self.actorPath1)
        let activeEventLoop: EventLoop = try XCTUnwrap(self.eventLoop)
        let serializationPool: SerializationPool = try SerializationPool(
            settings: SerializationPoolSettings(
                serializationGroups: [[firstActorPath]]
            ),
            serialization: actorSystem.serialization
        )
        defer { serializationPool.shutdown() }

        let probe: ActorTestProbe<String> = kit.makeTestProbe()

        // We are locking here to validate that the objects are being serialized
        // on different, separate threads, than the objects being deserialized
        let test1: SerializationPoolFirstPayload = SerializationPoolFirstPayload()
        test1.lock.lock()
        let promise1: EventLoopPromise<Serialization.Serialized> = activeEventLoop.makePromise()
        promise1.futureResult.whenSuccess { _ in
            probe.tell("p1")
        }
        SerializationPoolFirstPayload.deserializerLock.lock()
        let json: String = "{}"

        var buffer: ByteBuffer = self.allocator.buffer(capacity: json.count)
        buffer.writeString(json)
        let promise2: EventLoopPromise<SerializationPoolFirstPayload> = activeEventLoop.makePromise()
        promise2.futureResult.whenSuccess { _ in
            probe.tell("p2")
        }
        promise1.futureResult.whenFailure { print("\($0)") }

        serializationPool.serialize(message: test1, recipientPath: firstActorPath, promise: promise1)
        serializationPool.deserializeAny(
            from: .nioByteBuffer(buffer),
            using: self.manifest1,
            recipientPath: firstActorPath,
            callback: self.completePromise(SerializationPoolFirstPayload.self, promise2)
        )

        try probe.expectNoMessage(for: .milliseconds(20))

        SerializationPoolFirstPayload.deserializerLock.unlock()
        try probe.expectMessage("p2")

        test1.lock.unlock()
        try probe.expectMessage("p1")
    }
}
