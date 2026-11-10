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

internal struct SerializationPoolFirstPayload: Codable {
    internal enum CodingKeys: String, CodingKey {
        case test = "test"
    }

    internal static let deserializerLock: ClusterMutex = ClusterMutex()
    internal let lock: ClusterMutex

    internal init() {
        self.lock = ClusterMutex()
    }

    internal init(from _: Decoder) {
        self.lock = ClusterMutex()
        Self.deserializerLock.lock()
        Self.deserializerLock.unlock()
    }

    internal func encode(to encoder: Encoder) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(true, forKey: .test)
    }
}

internal struct SerializationPoolSecondPayload: Codable {
    internal enum CodingKeys: String, CodingKey {
        case test = "test"
    }

    internal static let deserializerLock: ClusterMutex = ClusterMutex()
    internal let lock: ClusterMutex

    internal init() {
        self.lock = ClusterMutex()
    }

    internal init(from _: Decoder) {
        self.lock = ClusterMutex()
        Self.deserializerLock.lock()
        Self.deserializerLock.unlock()
    }

    internal func encode(to encoder: Encoder) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(true, forKey: .test)
    }
}

// Shared fixtures are used by test extensions in separate files.
// swiftlint:disable test_case_accessibility
internal final class SerializationPoolTests: XCTestCase {

    internal let manifest1: Serialization.Manifest = Serialization.Manifest(
        serializerID: Serialization.SerializerID.foundationJSON,
        hint: Serialization.getTypeHint(
            SerializationPoolFirstPayload.self
        )
    )
    internal let manifest2: Serialization.Manifest = Serialization.Manifest(
        serializerID: Serialization.SerializerID.foundationJSON,
        hint: Serialization.getTypeHint(
            SerializationPoolSecondPayload.self
        )
    )

    internal var system: ClusterSystem?
    internal var testKit: ActorTestKit?

    internal var actorPath1: ActorPath?
    internal var actorPath2: ActorPath?

    internal var elg: MultiThreadedEventLoopGroup?
    internal var eventLoop: EventLoop?
    internal let allocator: ByteBufferAllocator = ByteBufferAllocator()

    internal func completePromise<T>(_: T.Type, _ promise: EventLoopPromise<T>) -> DeserializationCallback {
        DeserializationCallback { closureArgument in
            switch closureArgument {
            case .success(.message(let message as T)):
                promise.succeed(message)

            case .success(.message(let message)):
                promise.fail(TestError("Could not treat [\(message)]:\(type(of: message)) as \(T.self)"))

            case .success(.deadLetter(let deadLetter)):
                promise.fail(TestError("Got unexpected dead letter: \(deadLetter)"))

            case .failure(let error):
                promise.fail(error)
            }
        }
    }

    override internal func setUp() async throws {
        let actorSystem: ClusterSystem = await ClusterSystem("SerializationTests") { settings in
            settings.logging.baseLogger = NoopLogger.make()
            settings.serialization.register(SerializationPoolFirstPayload.self)
            settings.serialization.register(SerializationPoolSecondPayload.self)
        }
        self.system = actorSystem
        self.testKit = ActorTestKit(actorSystem)
        let group: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.elg = group
        self.eventLoop = group.next()
        self.actorPath1 = try ActorPath([ActorPathSegment("foo"), ActorPathSegment("bar")])
        self.actorPath2 = try ActorPath([ActorPathSegment("foo"), ActorPathSegment("baz")])
    }

    override internal func tearDown() async throws {
        let actorSystem: ClusterSystem = try XCTUnwrap(self.system)
        let group: MultiThreadedEventLoopGroup = try XCTUnwrap(self.elg)
        try await actorSystem.shutdown().wait()
        self.system = nil
        self.testKit = nil
        try await group.shutdownGracefully()
        self.eventLoop = nil
        self.elg = nil
    }

    internal func test_serializationPool_shouldSerializeMessagesInDefaultGroupOnCallingThread() throws {
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

        // We are locking here to validate that the object is being serialized
        // on the calling thread, because only then will it be able to reenter
        // the lock and return before `unlock` is called at the end of this
        // function
        let test1: SerializationPoolFirstPayload = SerializationPoolFirstPayload()
        test1.lock.lock()
        defer { test1.lock.unlock() }
        let promise1: NIO.EventLoopPromise<Serialization.Serialized> = activeEventLoop.makePromise()
        promise1.futureResult.whenSuccess { _ in
            probe.tell("p1")
        }

        let test2: SerializationPoolFirstPayload = SerializationPoolFirstPayload()
        test2.lock.lock()
        defer { test2.lock.unlock() }
        let promise2: EventLoopPromise<Serialization.Serialized> = activeEventLoop.makePromise()
        promise2.futureResult.whenSuccess { _ in
            probe.tell("p2")
        }

        serializationPool.serialize(message: test1, recipientPath: firstActorPath, promise: promise1)
        try probe.expectMessage("p1")
        serializationPool.serialize(message: test2, recipientPath: secondActorPath, promise: promise2)
        try probe.expectMessage("p2")
    }

    internal func test_serializationPool_shouldSerializeMessagesInTheSameNonDefaultGroupInSequence() throws {
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

        // We are locking here to validate that the objects are being serialized
        // on the same, separate thread, because only then will we not receive
        // the "p2" message when unlocking `test2.lock`, because it will still
        // wait on the `test1.lock`
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
        try probe.expectNoMessage(for: .milliseconds(20))

        test1.lock.unlock()
        try probe.expectMessage("p1")
        try probe.expectMessage("p2")
    }

}
// swiftlint:enable test_case_accessibility
