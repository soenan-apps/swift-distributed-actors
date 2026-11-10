import Distributed

@testable import DistributedCluster

internal distributed actor NestedActorSingleton: ClusterSingleton {
    internal typealias ActorSystem = ClusterSystem

    private let greeter: SingletonGreeter

    internal init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.greeter = SingletonGreeter(actorSystem: actorSystem)
    }

    internal distributed func actualID() -> ActorSystem.ActorID {
        self.id
    }

    internal distributed func getGreeter() -> SingletonGreeter {
        self.greeter
    }
}
