// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
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
import XCTest

@testable import DistributedCluster

internal distributed actor RemoteCallGreeter {
    internal typealias ActorSystem = ClusterSystem

    internal distributed func hello() -> String {
        "hello"
    }

    internal distributed func helloThrow(codable: Bool) throws -> String {
        if codable {
            throw GreeterCodableError()
        }
        throw GreeterNonCodableError()
    }

    internal distributed func hello(delayNanos: UInt64) async throws -> String {
        try await Task.sleep(nanoseconds: delayNanos)
        return self.hello()
    }

    internal distributed func muted() {
        // A Void invocation intentionally has no response payload.
    }

    internal distributed func mutedThrow(codable: Bool) throws {
        if codable {
            throw GreeterCodableError()
        }
        throw GreeterNonCodableError()
    }

    internal distributed func muted(delayNanos: UInt64) async throws {
        try await Task.sleep(nanoseconds: delayNanos)
        self.muted()
    }

    internal distributed func genericEcho<T: Sendable & Codable>(_ message: T) -> T {
        message
    }
}

internal struct GreeterCodableError: Error, Codable {}
private struct GreeterNonCodableError: Error {}
internal struct AnotherGreeterCodableError: Error, Codable {}

internal final class RemoteCallTests: ClusteredActorSystemsXCTestCase {
    internal func test_remoteCall() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.serialization.registerInbound(GreeterCodableError.self)
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.serialization.registerInbound(GreeterCodableError.self)
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let value: String = try await shouldNotThrow {
            try await remoteGreeterRef.hello()
        }
        value.shouldEqual("hello")
    }

    internal func test_remoteCall_shouldCarryBackThrownError_Codable() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.serialization.registerInbound(GreeterCodableError.self)
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.serialization.registerInbound(GreeterCodableError.self)
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let error: Error = try await shouldThrow {
            _ = try await remoteGreeterRef.helloThrow(codable: true)
        }
        guard error is GreeterCodableError else {
            throw TestError("Expected GreeterCodableError, got \(error)")
        }
    }

    internal func test_remoteCall_shouldCarryBackThrownError_nonCodable() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.serialization.registerInbound(GreeterCodableError.self)
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.serialization.registerInbound(GreeterCodableError.self)
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let error: Error = try await shouldThrow {
            _ = try await remoteGreeterRef.helloThrow(codable: false)
        }
        guard let remoteCallError = error as? GenericRemoteCallError else {
            throw TestError("Expected GenericRemoteCallError, got \(error)")
        }
        remoteCallError.message.shouldStartWith(prefix: "Remote call error of [GreeterNonCodableError] type occurred")
    }

    internal func test_remoteCallVoid() async throws {
        let local: ClusterSystem = await setUpNode("local")
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.serialization.registerInbound(GreeterCodableError.self)
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        try await shouldNotThrow {
            try await remoteGreeterRef.muted()
        }
    }

    internal func test_remoteCallVoid_shouldCarryBackThrownError_Codable() async throws {
        let local: ClusterSystem = await setUpNode("local")
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.serialization.registerInbound(GreeterCodableError.self)
        }
        try await self.joinNodes(node: local, with: remote)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let error: Error = try await shouldThrow {
            try await remoteGreeterRef.mutedThrow(codable: true)
        }
        guard error is GreeterCodableError else {
            _ = self.testKit(local).fail("Expected GreeterCodableError, got \(error)")
            return
        }
    }

    internal func test_remoteCallVoid_shouldCarryBackThrownError_nonCodable() async throws {
        let local: ClusterSystem = await setUpNode("local")
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.serialization.registerInbound(GreeterCodableError.self)
        }
        try await self.joinNodes(node: local, with: remote)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let error: Error = try await shouldThrow {
            try await remoteGreeterRef.mutedThrow(codable: false)
        }
        guard let remoteCallError = error as? GenericRemoteCallError else {
            throw TestError("Expected GenericRemoteCallError, got \(error)")
        }
        remoteCallError.message.shouldStartWith(prefix: "Remote call error of [GreeterNonCodableError] type occurred")
    }

    internal func test_remoteCall_shouldConfigureTimeout() async throws {
        let local: ClusterSystem = await setUpNode("local")
        let remote: ClusterSystem = await setUpNode("remote")
        try await self.joinNodes(node: local, with: remote)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let error: Error = try await shouldThrow {
            try await RemoteCall.with(timeout: .milliseconds(200)) {
                _ = try await remoteGreeterRef.hello(delayNanos: 3_000_000_000)
            }
        }

        guard let remoteCallError = error as? RemoteCallError,
            case .timedOut(_, let timeoutError) =
                remoteCallError.underlying.error
        else {
            throw TestError("Expected RemoteCallError.timedOut, got \(error)")
        }
        guard timeoutError.timeout == .milliseconds(200) else {
            throw TestError("Expected timeout to be 200 milliseconds but was \(timeoutError.timeout)")
        }
    }

}
