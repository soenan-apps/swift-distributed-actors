// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
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

extension ClusterSingletonBoss {
    /// Forwards a call to the active singleton, waiting for allocation if necessary.
    internal func forwardOrStashRemoteCall<Err, Res>(
        target: RemoteCallTarget,
        invocation: ActorSystem.InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res where Err: Error, Res: Codable & SendableMetatype {
        do {
            let singleton: Act = try await self.findSingleton(target: target)
            self.log.trace(
                "Forwarding call to \(target)",
                metadata: self.metadata([
                    "remoteCall/target": "\(target)",
                    "remoteCall/invocation": "\(invocation)",
                ])
            )
            var forwardedInvocation: ActorSystem.InvocationEncoder = invocation
            if targetNode == selfNode, let localSingleton = self.targetSingleton {
                assert(
                    localSingleton.id.node == selfNode,
                    "Target singleton node and targetNode were not the same! "
                        + "TargetNode: \(targetNode?.debugDescription ?? "UNKNOWN TARGET NODE"),"
                        + " singleton.id.node: \(localSingleton.id.node)"
                )
                return try await localSingleton.actorSystem.localCall(
                    on: localSingleton,
                    target: target,
                    invocation: &forwardedInvocation,
                    throwing: throwing,
                    returning: returning
                )
            }
            return try await singleton.actorSystem.remoteCall(
                on: singleton,
                target: target,
                invocation: &forwardedInvocation,
                throwing: throwing,
                returning: returning
            )
        } catch {
            log.warning(
                "Failed forwarding call to \(target)",
                metadata: [
                    "remoteCall/target": "\(target)",
                    "remoteCall/invocation": "\(invocation)",
                ]
            )
            throw error
        }
    }

    /// Forwards a void call, waiting for singleton allocation if necessary.
    internal func forwardOrStashRemoteCallVoid<Err>(
        target: RemoteCallTarget,
        invocation: ActorSystem.InvocationEncoder,
        throwing: Err.Type
    ) async throws where Err: Error {
        self.log.trace("ENTER forwardOrStashRemoteCallVoid \(target)")
        let singleton: Act = try await self.findSingleton(target: target)
        self.log.trace(
            "Forwarding call to [\(target)] to [\(singleton) @ \(singleton.id)]",
            metadata: self.metadata([
                "remoteCall/target": "\(target)",
                "remoteCall/invocation": "\(invocation)",
            ])
        )
        var forwardedInvocation: ActorSystem.InvocationEncoder = invocation
        if targetNode == selfNode, let localSingleton = self.targetSingleton {
            self.log.trace("ENTER forwardOrStashRemoteCallVoid \(target) -> DIRECT LOCAL CALL")
            assert(
                localSingleton.id.node == selfNode,
                "Target singleton node and targetNode were not the same! "
                    + "TargetNode: \(targetNode?.debugDescription ?? "UNKNOWN TARGET NODE"),"
                    + " singleton.id.node: \(localSingleton.id.node)"
            )
            return try await localSingleton.actorSystem.localCallVoid(
                on: localSingleton,
                target: target,
                invocation: &forwardedInvocation,
                throwing: throwing
            )
        }
        return try await singleton.actorSystem.remoteCallVoid(
            on: singleton,
            target: target,
            invocation: &forwardedInvocation,
            throwing: throwing
        )
    }
}
