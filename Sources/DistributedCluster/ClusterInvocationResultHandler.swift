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
import Logging
import NIO

public struct ClusterInvocationResultHandler: DistributedTargetInvocationResultHandler {
    /// Codable準拠はisolation domainをまたいで使用できる必要がある。
    /// 値自体のSendable準拠は要求しない。
    public typealias SerializationRequirement = any Codable & SendableMetatype

    internal enum State {
        case remoteCall(
            system: ClusterSystem,
            callID: ClusterSystem.CallID,
            channel: Channel,
            recipient: ClusterSystem.ActorID
        )
        case localDirectReturn(CheckedContinuation<Any, Error>)
    }

    internal let state: State

    internal init(
        system: ClusterSystem,
        callID: ClusterSystem.CallID,
        channel: Channel,
        recipient: ClusterSystem.ActorID
    ) {
        self.state = .remoteCall(system: system, callID: callID, channel: channel, recipient: recipient)
    }

    internal init(directReturnContinuation: CheckedContinuation<Any, Error>) {
        self.state = .localDirectReturn(directReturnContinuation)
    }

    public func onReturn<Success: Codable & SendableMetatype>(value: Success) async throws {
        switch self.state {
        case .localDirectReturn(let directReturnContinuation):
            directReturnContinuation.resume(returning: value)

        case let .remoteCall(system, callID, channel, recipient):
            system.log.trace(
                "Result handler, onReturn",
                metadata: [
                    "call/id": "\(callID)",
                    "type": "\(Success.self)",
                ]
            )

            let reply: RemoteCallReply<Success> = RemoteCallReply<Success>(callID: callID, value: value)
            try await channel.writeAndFlush(
                TransportEnvelope(envelope: Payload(payload: .message(reply)), recipient: recipient)
            )
        }
    }

    public func onReturnVoid() async throws {
        switch self.state {
        case .localDirectReturn(let directReturnContinuation):
            directReturnContinuation.resume(returning: ())

        case let .remoteCall(system, callID, channel, recipient):
            system.log.debug(
                "Result handler, onReturnVoid",
                metadata: [
                    "call/id": "\(callID)"
                ]
            )

            let reply: RemoteCallReply<Done> = RemoteCallReply<Done>(callID: callID, value: .done)
            try await channel.writeAndFlush(
                TransportEnvelope(envelope: Payload(payload: .message(reply)), recipient: recipient)
            )
        }
    }

    public func onThrow<Err: Error>(error: Err) async throws {
        switch self.state {
        case .localDirectReturn(let directReturnContinuation):
            directReturnContinuation.resume(throwing: error)

        case let .remoteCall(system, callID, channel, recipient):
            system.log.debug("Result handler, onThrow: \(error)", metadata: ["call/id": "\(callID)"])

            let errorType: Any.Type = type(of: error as Any)
            let reply: RemoteCallReply<Done>

            if let codableError = error as? (Error & Codable) {
                switch system.settings.remoteCall.codableErrorAllowance.underlying {
                case .custom(let allowedTypeOIDs) where allowedTypeOIDs.contains(ObjectIdentifier(errorType)):
                    reply = .init(callID: callID, error: codableError)

                case .all:  // compiler gets confused if this is grouped together with above
                    reply = .init(callID: callID, error: codableError)

                default:
                    reply = .init(callID: callID, error: GenericRemoteCallError(errorType: errorType))
                }
            } else {
                reply = .init(callID: callID, error: GenericRemoteCallError(errorType: errorType))
            }
            try await channel.writeAndFlush(
                TransportEnvelope(envelope: Payload(payload: .message(reply)), recipient: recipient)
            )
        }
    }

}
