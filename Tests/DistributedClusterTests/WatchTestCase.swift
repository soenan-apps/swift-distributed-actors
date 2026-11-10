import DistributedActorsTestKit

@testable import DistributedCluster

internal class WatchTestCase: SingleClusterSystemXCTestCase {
    internal typealias Done = WatchDone
    internal typealias RomeoMessage = WatchRomeoMessage
    internal typealias JulietMessage = WatchJulietMessage
    internal typealias StoppableRefMessage = WatchStoppableMessage

    internal struct TakePoisonError: Error {}

    internal func stopOnAnyMessage(probe: ActorRef<String>?) -> Behavior<StoppableRefMessage> {
        .receive { context, message in
            switch message {
            case .stop:
                probe?.tell("I (\(context.path.name)) will now stop")
                return .stop
            }
        }
    }
}
