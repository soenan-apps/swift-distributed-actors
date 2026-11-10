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

import Atomics
import Distributed
import DistributedActorsConcurrencyHelpers
import Foundation
import Logging

extension ClusterSystem {
    /// 分散actor呼出しの引数を記録するencoderを作成する。
    public func makeInvocationEncoder() -> InvocationEncoder {
        InvocationEncoder(system: self)
    }

    /// 戻り値のある分散actor呼出しを実行する。
    nonisolated(nonsending) public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error,
        Res: Codable & SendableMetatype {
        if let interceptor = actor.id.context.remoteCallInterceptor {
            return try await interceptor.interceptRemoteCall(
                on: actor,
                target: target,
                invocation: &invocation,
                throwing: throwing,
                returning: returning
            )
        }

        guard __isRemoteActor(actor), actor.id.node != self.cluster.node else {
            // It actually is a remote call, so redirect it to local call-path.
            // Such calls can happen when we deal with interceptors and proxies;
            // To make their lives easier, we centralize the noticing when a call is local and dispatch it from here.
            return try await self.localCall(
                on: actor,
                target: target,
                invocation: &invocation,
                throwing: throwing,
                returning: returning
            )
        }

        let recipient: RemoteClusterActorPersonality<InvocationMessage> = try self.remoteCallRecipient(
            for: actor.id,
            target: target
        )
        let arguments: [Data] = invocation.arguments

        let reply: RemoteCallReply<Res> = try await self.withCallID(on: actor.id, target: target) { callID in
            let message: InvocationMessage = InvocationMessage(
                callID: callID,
                targetIdentifier: target.identifier,
                genericSubstitutions: invocation.genericSubstitutions,
                arguments: arguments
            )

            recipient.sendInvocation(message)
        }

        if let error = reply.thrownError {
            throw error
        }
        guard let value = reply.value else {
            throw RemoteCallError(
                .invalidReply(reply.callID),
                on: actor.id,
                target: target
            )
        }
        return value
    }

    /// 戻り値のない分散actor呼出しを実行する。
    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error {
        if let interceptor = actor.id.context.remoteCallInterceptor {
            return try await interceptor.interceptRemoteCallVoid(
                on: actor,
                target: target,
                invocation: &invocation,
                throwing: throwing
            )
        }

        guard __isRemoteActor(actor), actor.id.node != self.cluster.node else {
            // It actually is a remote call, so redirect it to local call-path.
            // Such calls can happen when we deal with interceptors and proxies;
            // To make their lives easier, we centralize the noticing when a call is local and dispatch it from here.
            return try await self.localCallVoid(on: actor, target: target, invocation: &invocation, throwing: throwing)
        }

        let recipient: RemoteClusterActorPersonality<InvocationMessage> = try self.remoteCallRecipient(
            for: actor.id,
            target: target
        )
        let arguments: [Data] = invocation.arguments

        let reply: RemoteCallReply<Done> = try await self.withCallID(on: actor.id, target: target) { callID in
            let message: InvocationMessage = InvocationMessage(
                callID: callID,
                targetIdentifier: target.identifier,
                genericSubstitutions: invocation.genericSubstitutions,
                arguments: arguments
            )
            recipient.sendInvocation(message)
        }

        if let error = reply.thrownError {
            throw error
        }
    }

    private func withCallID<Reply>(
        on actorID: ActorID,
        target: RemoteCallTarget,
        body: (CallID) -> Void
    ) async throws -> Reply
    where Reply: AnyRemoteCallReply {
        let callID: UUID = UUID()

        let timeout: Duration = RemoteCall.timeout ?? self.settings.remoteCall.defaultTimeout
        let timeoutTask: Task<Void, Error> = Task.detached {
            try await Task.sleep(nanoseconds: UInt64(timeout.nanoseconds))
            guard !Task.isCancelled else {
                return
            }

            self.inFlightCallLock.withLockVoid {
                guard let continuation = self.inFlightCalls.removeValue(forKey: callID) else {
                    // remoteCall was already completed successfully, nothing to do here
                    return
                }

                let error: Error
                if self.isShuttingDown {
                    // If the system is shutting down, we should offer a more specific error;
                    //
                    // We may not be getting responses simply because we've shut down associations
                    // and cannot receive them anymore.
                    // Some subsystems may ignore those errors, since they are "expected".
                    //
                    // If we're shutting down, it is okay to not get acknowledgements to calls for example,
                    // and we don't care about them missing -- we're shutting down anyway.
                    error = RemoteCallError(.clusterAlreadyShutDown, on: actorID, target: target)
                } else {
                    error = RemoteCallError(
                        .timedOut(
                            callID,
                            TimeoutError(
                                message: "Remote call [\(callID)] to [\(target)](\(actorID)) timed out",
                                timeout: timeout
                            )
                        ),
                        on: actorID,
                        target: target
                    )
                }

                continuation.resume(throwing: error)
            }
        }
        defer {
            timeoutTask.cancel()
        }

        let reply: any AnyRemoteCallReply = try await withCheckedThrowingContinuation { continuation in
            self.inFlightCallLock.withLock {
                self.inFlightCalls[callID] = continuation  // this is to be resumed from an incoming reply or timeout
            }
            body(callID)
        }

        guard let typedReply = reply as? Reply else {
            // ClusterInvocationResultHandler.onThrow returns RemoteCallReply<Done> for both
            // remoteCallVoid and remoteCall (i.e., it doesn't send back RemoteCallReply<Res>).
            // The guard check above fails for the latter use-case because of type mismatch.
            // The if-block converts the error reply to the proper type then returns it.
            if let thrownError = reply.thrownError {
                return Reply(callID: reply.callID, error: thrownError)
            }

            self.log.error("Expected [\(Reply.self)] but got [\(type(of: reply as Any))]")
            throw RemoteCallError(.invalidReply(callID), on: actorID, target: target)
        }
        return typedReply
    }

    private func remoteCallRecipient(
        for actorID: ActorID,
        target: RemoteCallTarget
    ) throws -> RemoteClusterActorPersonality<InvocationMessage> {
        guard let shell = self.clusterShell else {
            throw RemoteCallError(
                .clusterAlreadyShutDown,
                on: actorID,
                target: target
            )
        }
        guard self.shutdownFlag.load(ordering: .relaxed) == 0 else {
            throw RemoteCallError(
                .clusterAlreadyShutDown,
                on: actorID,
                target: target
            )
        }
        return RemoteClusterActorPersonality(shell: shell, id: actorID.asRemote, system: self)
    }
}
