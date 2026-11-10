// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

import Distributed

internal struct ClusterSingletonRemoteCallInterceptor<Singleton: ClusterSingleton>: RemoteCallInterceptor {
    internal let system: ClusterSystem
    internal let singletonBoss: ClusterSingletonBoss<Singleton>

    nonisolated(nonsending) internal func interceptRemoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout ClusterSystem.InvocationEncoder,
        throwing _: Err.Type,
        returning _: Res.Type
    ) async throws -> Res
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error,
        Res: Codable & SendableMetatype {
        guard actor is Singleton else {
            fatalError("This interceptor expects actor type [\(Singleton.self)] but got [\(Act.self)]")
        }

        let capturedInvocation: ClusterSystem.InvocationEncoder = invocation
        let result: Res? = try await self.singletonBoss.whenLocal { localBoss in
            try await localBoss.forwardOrStashRemoteCall(
                target: target,
                invocation: capturedInvocation,
                throwing: Err.self,
                returning: Res.self
            )
        }

        guard let result else {
            fatalError("Unexpected remote call")
        }
        return result
    }

    internal func interceptRemoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout ClusterSystem.InvocationEncoder,
        throwing: Err.Type
    ) async throws
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error {
        guard actor is Singleton else {
            fatalError("This interceptor expects actor type [\(Singleton.self)] but got [\(Act.self)]")
        }

        let capturedInvocation: ClusterSystem.InvocationEncoder = invocation
        try await self.singletonBoss.whenLocal { localBoss in
            try await localBoss.forwardOrStashRemoteCallVoid(
                target: target,
                invocation: capturedInvocation,
                throwing: throwing
            )
        }
    }
}
