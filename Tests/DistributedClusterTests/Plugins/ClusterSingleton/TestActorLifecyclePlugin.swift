import Distributed
import DistributedActorsConcurrencyHelpers

@testable import DistributedCluster

internal final class TestActorLifecyclePlugin: ActorLifecyclePlugin {
    private let actorReady: (any DistributedActor) -> Void
    private let actorResigned: (ActorID) -> Void
    private let started: (ClusterSystem) -> Void
    private let stopped: (ClusterSystem) -> Void
    private let lock: ClusterMutex = ClusterMutex()

    internal var key: Key { "$testClusterHook" }

    internal init(
        onActorReady: @escaping (any DistributedActor) -> Void,
        onResignID: @escaping (ActorID) -> Void,
        onStart: @escaping (ClusterSystem) -> Void,
        onStop: @escaping (ClusterSystem) -> Void
    ) {
        self.actorReady = onActorReady
        self.actorResigned = onResignID
        self.started = onStart
        self.stopped = onStop
    }

    internal func onActorReady<Act: DistributedActor>(_ actor: Act) where Act.ID == ClusterSystem.ActorID {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.actorReady(actor)
    }

    internal func onResignID(_ id: ClusterSystem.ActorID) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.actorResigned(id)
    }

    internal func start(_ system: ClusterSystem) {
        self.started(system)
    }

    internal func stop(_ system: ClusterSystem) {
        self.stopped(system)
    }
}
