@testable import DistributedCluster

internal enum WatchRomeoMessage: Codable {
    case pleaseWatch(juliet: ActorRef<WatchJulietMessage>, probe: ActorRef<WatchDone>)

    private enum DiscriminatorKeys: String, Codable {
        case pleaseWatch = "pleaseWatch"
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "_case"
        case pleaseWatchJuliet = "pleaseWatch_juliet"
        case pleaseWatchProbe = "pleaseWatch_probe"
    }

    internal init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(DiscriminatorKeys.self, forKey: .kind) {
        case .pleaseWatch:
            let juliet: ActorRef<WatchJulietMessage> = try container.decode(
                ActorRef<WatchJulietMessage>.self,
                forKey: .pleaseWatchJuliet
            )
            let probe: ActorRef<WatchDone> = try container.decode(ActorRef<WatchDone>.self, forKey: .pleaseWatchProbe)

            self = .pleaseWatch(juliet: juliet, probe: probe)
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .pleaseWatch(juliet, probe):
            try container.encode(juliet, forKey: .pleaseWatchJuliet)
            try container.encode(probe, forKey: .pleaseWatchProbe)
        }
    }
}
