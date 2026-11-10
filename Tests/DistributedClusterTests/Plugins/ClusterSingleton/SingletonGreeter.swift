import Distributed

@testable import DistributedCluster

internal distributed actor SingletonGreeter {
    internal typealias ActorSystem = ClusterSystem
    internal init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    internal distributed func greet() {
        print("Hello!")
    }
}
