import Distributed
import DistributedActorsTestKit

@testable import DistributedCluster

internal distributed actor TheSingleton: ClusterSingleton {
    internal typealias ActorSystem = ClusterSystem

    private let greeting: String

    internal init(greeting: String, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.greeting = greeting
    }

    internal distributed func greet(name: String) -> String {
        "\(self.greeting) \(name)! (from node: \(self.id.node), id: \(self.id.detailedDescription))"
    }
}
