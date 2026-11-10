@testable import DistributedCluster

internal struct NoAcksTestGossipLogic: GossipLogic {
    internal typealias Gossip = GossiperTestPayload
    internal typealias Acknowledgement = String

    internal let probe: ActorRef<String>
    internal var payload: Gossip = Gossip("Hello")

    internal func selectPeers(_ peers: [AddressableActorRef]) -> [AddressableActorRef] {
        peers
    }

    internal func makePayload(target _: AddressableActorRef) -> Gossip? {
        self.payload
    }

    internal func receiveAcknowledgement(
        _ acknowledgement: Acknowledgement,
        from peer: AddressableActorRef,
        confirming gossip: Gossip
    ) {
        self.probe.tell("un-expected acknowledgement: \(acknowledgement) from \(peer) confirming \(gossip)")
    }

    internal func receiveGossip(_: Gossip, from _: AddressableActorRef) -> Acknowledgement? {
        nil
    }

    internal mutating func receiveLocalGossipUpdate(_ gossip: Gossip) {
        self.payload = gossip
    }
}
