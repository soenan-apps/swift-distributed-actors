import Distributed

@testable import DistributedCluster

internal distributed actor LifecycleHookActor {
    internal let customID: String

    internal init(
        actorSystem: ActorSystem,
        customID: String
    ) {
        self.actorSystem = actorSystem
        self.customID = customID
    }

    internal distributed func getID() -> String {
        self.customID
    }
}
