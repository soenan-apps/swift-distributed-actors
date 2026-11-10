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
import Foundation
import Logging

extension ClusterSystem {
    /// Able to direct a `remoteCall` initiated call, right into a local invocation.
    /// This is used to perform proxying to local actors, for such features like the cluster singleton or similar.
    nonisolated(nonsending) internal func localCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing _: Err.Type,
        returning _: Res.Type
    ) async throws -> Res
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error,
        Res: Codable & SendableMetatype {
        precondition(
            self.cluster.node == actor.id.node,
            """
            Attempted to localCall an actor whose ID was a different node: [\(actor.id)], \
            current node: \(self.cluster.node)
            """
        )
        self.log.trace(
            "Execute local call",
            metadata: [
                "actor/id": "\(actor.id.fullDescription)",
                "target": "\(target)",
            ]
        )

        let anyReturn: Any = try await withCheckedThrowingContinuation { continuation in
            Task { [invocation] in
                var directDecoder: ClusterInvocationDecoder = ClusterInvocationDecoder(
                    system: self,
                    invocation: invocation
                )
                let directReturnHandler: ClusterInvocationResultHandler = ClusterInvocationResultHandler(
                    directReturnContinuation: continuation
                )

                do {
                    try await executeDistributedTarget(
                        on: actor,
                        target: target,
                        invocationDecoder: &directDecoder,
                        handler: directReturnHandler
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard let wellTypedReturn = anyReturn as? Res else {
            throw RemoteCallError(
                .illegalReplyType(UUID(), expected: Res.self, got: type(of: anyReturn)),
                on: actor.id,
                target: target
            )
        }

        return wellTypedReturn
    }

    /// Able to direct a `remoteCallVoid` initiated call, right into a local invocation.
    /// This is used to perform proxying to local actors, for such features like the cluster singleton or similar.
    internal func localCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing _: Err.Type
    ) async throws
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error {
        precondition(
            self.cluster.node == actor.id.node,
            """
            Attempted to localCall an actor whose ID was a different node: [\(actor.id)], \
            current node: \(self.cluster.node)
            """
        )
        self.log.trace(
            "Execute local void call",
            metadata: [
                "actor/id": "\(actor.id.fullDescription)",
                "target": "\(target)",
            ]
        )

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
            Task { [invocation] in
                var directDecoder: ClusterInvocationDecoder = ClusterInvocationDecoder(
                    system: self,
                    invocation: invocation
                )
                let directReturnHandler: ClusterInvocationResultHandler = ClusterInvocationResultHandler(
                    directReturnContinuation: continuation
                )

                do {
                    try await executeDistributedTarget(
                        on: actor,
                        target: target,
                        invocationDecoder: &directDecoder,
                        handler: directReturnHandler
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
