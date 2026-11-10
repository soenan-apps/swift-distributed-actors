@testable import DistributedCluster

internal struct InspectOfferedPeersTestGossipLogic: GossipLogic {
    internal typealias Gossip = GossiperTestPayload
    internal typealias Acknowledgement = String

    internal let offeredPeersProbe: ActorRef<[AddressableActorRef]>
    internal var payload: Gossip?

    internal func selectPeers(_ peers: [AddressableActorRef]) -> [AddressableActorRef] {
        self.offeredPeersProbe.tell(peers)
        return []
    }

    internal func makePayload(target _: AddressableActorRef) -> Gossip? {
        self.payload
    }

    internal func receiveGossip(_: Gossip, from _: AddressableActorRef) -> Acknowledgement? {
        nil
    }

    internal mutating func receiveLocalGossipUpdate(_ gossip: Gossip) {
        self.payload = gossip
    }
}
