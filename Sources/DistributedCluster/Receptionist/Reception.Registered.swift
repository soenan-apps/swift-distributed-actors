import Distributed

extension Reception.Registered where Guest: ReceivesMessages {
    internal var ref: ActorRef<Guest.Message> {
        self.guest.ref
    }
}

extension Reception.Registered where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
    /// Resolves the registered distributed actor using its original actor system.
    public var actor: Guest {
        get throws {
            try Guest.resolve(id: self.guest.ref.id, using: self.guest.actorSystem)
        }
    }
}
