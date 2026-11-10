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

extension RemoteCallTests {
    internal func test_remoteCallVoid_shouldConfigureTimeout() async throws {
        let local: ClusterSystem = await setUpNode("local")
        let remote: ClusterSystem = await setUpNode("remote")
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let error: Error = try await shouldThrow {
            try await RemoteCall.with(timeout: .milliseconds(200)) {
                try await remoteGreeterRef.muted(delayNanos: 3_000_000_000)
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

    internal func test_remoteCallGeneric() async throws {
        let local: ClusterSystem = await setUpNode("local")
        let remote: ClusterSystem = await setUpNode("remote")
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let message: String = "hello"
        let value: String = try await shouldNotThrow {
            try await remoteGreeterRef.genericEcho(message)
        }
        value.shouldEqual(message)
    }

    internal func test_remoteCall_codableErrorAllowList_all() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.remoteCall.codableErrorAllowance = .all
            settings.serialization.registerInbound(GreeterCodableError.self)
            settings.serialization.registerInbound(AnotherGreeterCodableError.self)
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.remoteCall.codableErrorAllowance = .all
            settings.serialization.registerInbound(GreeterCodableError.self)
            settings.serialization.registerInbound(AnotherGreeterCodableError.self)
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

    internal func test_remoteCall_codableErrorAllowList_none() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.remoteCall.codableErrorAllowance = .genericOnly
            settings.serialization.registerInbound(GreeterCodableError.self)
            settings.serialization.registerInbound(AnotherGreeterCodableError.self)
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.remoteCall.codableErrorAllowance = .genericOnly
            settings.serialization.registerInbound(GreeterCodableError.self)
            settings.serialization.registerInbound(AnotherGreeterCodableError.self)
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let error: Error = try await shouldThrow {
            _ = try await remoteGreeterRef.helloThrow(codable: true)
        }
        guard let remoteCallError = error as? GenericRemoteCallError else {
            throw TestError("Expected GenericRemoteCallError, got \(error)")
        }
        remoteCallError.message.shouldStartWith(prefix: "Remote call error of [GreeterCodableError] type occurred")
    }

    internal func test_remoteCall_customCodableErrorAllowList_errorInList() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.remoteCall.codableErrorAllowance = .custom(
                allowedTypes: [
                    GreeterCodableError.self,
                    AnotherGreeterCodableError.self,
                ]
            )
            settings.serialization.registerInbound(GreeterCodableError.self)
            settings.serialization.registerInbound(AnotherGreeterCodableError.self)
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.remoteCall.codableErrorAllowance = .custom(
                allowedTypes: [
                    GreeterCodableError.self,
                    AnotherGreeterCodableError.self,
                ]
            )
            settings.serialization.registerInbound(GreeterCodableError.self)
            settings.serialization.registerInbound(AnotherGreeterCodableError.self)
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

    internal func test_remoteCall_customCodableErrorAllowList_errorInListButNotRegistered() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.remoteCall.codableErrorAllowance = .custom(
                allowedTypes: [
                    GreeterCodableError.self,
                    AnotherGreeterCodableError.self,
                ]
            )
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.remoteCall.codableErrorAllowance = .custom(
                allowedTypes: [
                    GreeterCodableError.self,
                    AnotherGreeterCodableError.self,
                ]
            )
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let error: Error = try await shouldThrow {
            try await RemoteCall.with(timeout: .milliseconds(200)) {
                _ = try await remoteGreeterRef.helloThrow(codable: true)
            }
        }
        guard let remoteCallError = error as? RemoteCallError, case .timedOut = remoteCallError.underlying.error else {
            throw TestError("Expected RemoteCallError.timedOut, got \(error)")
        }
    }

    internal func test_remoteCall_customCodableErrorAllowList_errorNotInList() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.remoteCall.codableErrorAllowance = .custom(allowedTypes: [AnotherGreeterCodableError.self])
            settings.serialization.registerInbound(GreeterCodableError.self)
            settings.serialization.registerInbound(AnotherGreeterCodableError.self)
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.remoteCall.codableErrorAllowance = .custom(allowedTypes: [AnotherGreeterCodableError.self])
            settings.serialization.registerInbound(GreeterCodableError.self)
            settings.serialization.registerInbound(AnotherGreeterCodableError.self)
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let greeter: RemoteCallGreeter = RemoteCallGreeter(actorSystem: local)
        let remoteGreeterRef: RemoteCallGreeter = try RemoteCallGreeter.resolve(id: greeter.id, using: remote)

        let error: Error = try await shouldThrow {
            _ = try await remoteGreeterRef.helloThrow(codable: true)
        }
        guard let remoteCallError = error as? GenericRemoteCallError else {
            throw TestError("Expected GenericRemoteCallError, got \(error)")
        }
        remoteCallError.message.shouldStartWith(prefix: "Remote call error of [GreeterCodableError] type occurred")
    }
}
