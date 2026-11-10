import Distributed
import DistributedActorsTestKit

@testable import DistributedCluster

internal distributed actor LifecycleTestSingleton: ClusterSingleton {
    internal typealias ActorSystem = ClusterSystem

    internal let probe: ActorTestProbe<String>

    internal init(probe: ActorTestProbe<String>, actorSystem: ActorSystem) {
        self.probe = probe
        self.actorSystem = actorSystem

        probe.tell("init: \(self.id)")
    }

    internal func activateSingleton() {
        self.probe.tell("activate: \(self.id)")
    }

    internal func passivateSingleton() {
        self.probe.tell("passivate: \(self.id)")
    }

    deinit {
        guard __isLocalActor(self) else {
            return
        }

        self.probe.tell("deinit \(self.id)")
    }
}
