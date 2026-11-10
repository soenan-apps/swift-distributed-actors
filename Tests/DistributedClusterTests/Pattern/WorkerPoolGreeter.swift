import Distributed
import DistributedActorsTestKit

@testable import DistributedCluster

internal distributed actor WorkerPoolGreeter: DistributedWorker {
    internal typealias ActorSystem = ClusterSystem
    internal typealias WorkItem = String
    internal typealias WorkResult = String

    internal let probe: ActorTestProbe<String>

    internal init(probe: ActorTestProbe<String>, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.probe = probe
    }

    internal init(
        probe: ActorTestProbe<String>,
        actorSystem: ActorSystem,
        key: DistributedReception.Key<WorkerPoolGreeter>
    ) async {
        self.actorSystem = actorSystem
        self.probe = probe
        await self.actorSystem.receptionist.checkIn(self, with: key)
    }

    internal distributed func submit(work: WorkItem) -> WorkResult {
        self.probe.tell("work:\(work) at \(self.id)")
        return "hello \(work)"
    }

    deinit {
        self.probe.tell("Greeter deinit")
    }

}
