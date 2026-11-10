import Distributed

internal protocol RemoteCallInterceptor {
    nonisolated(nonsending) func interceptRemoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout ClusterSystem.InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error,
        Res: Codable & SendableMetatype

    func interceptRemoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout ClusterSystem.InvocationEncoder,
        throwing: Err.Type
    ) async throws
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error
}
