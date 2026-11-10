import Foundation

/// Specifically to be implemented ONLY by `system.receptionist` i.e. the `SystemReceptionist`.
internal protocol BaseReceptionistOperations {
    /// Registers passed in `actor` in the systems receptionist with given id.
    ///
    /// - Parameters:
    ///   - actor: the actor to register with the receptionist. It may be `context.myself` or any other actor, however
    ///   generally it is recommended to let actors register themselves when they are "ready".
    ///   - id: id used for the key identifier. E.g. when aiming to register all instances of "Sensor" in the same
    ///   group, the recommended id is "sensors".
    @discardableResult
    func register<Guest>(
        _ guest: Guest,
        as id: String,
        replyTo: ActorRef<Reception.Registered<Guest>>?
    ) -> Reception.Key<Guest> where Guest: ReceptionistGuest

    /// Registers passed in `actor` in the systems receptionist with given id.
    ///
    /// - Parameters:
    ///   - actor: the actor to register with the receptionist. It may be `context.myself` or any other actor, however
    ///   generally it is recommended to let actors register themselves when they are "ready". ///   - id: id used for
    ///   the key identifier. E.g. when aiming to register all instances of "Sensor" in the same group, the recommended
    ///   id is "sensors".
    @discardableResult
    func register<Guest>(
        _ guest: Guest,
        with key: Reception.Key<Guest>,
        replyTo: ActorRef<Reception.Registered<Guest>>?
    ) -> Reception.Key<Guest> where Guest: ReceptionistGuest

    /// Subscribe to changes in checked-in actors under given `key`.
    ///
    /// The `subscriber` actor will be notified with `Reception.Listing<M>` messages when new actors register, leave or
    /// die, under the passed in key.
    func subscribe<Guest>(
        _ subscriber: ActorRef<Reception.Listing<Guest>>,
        to key: Reception.Key<Guest>
    ) where Guest: ReceptionistGuest

    /// Perform a *single* lookup for an actor identified by the passed in `key`.
    ///
    /// - Parameters:
    ///   - key: selects which actors we are interested in.
    func lookup<Guest>(
        _ key: Reception.Key<Guest>,
        replyTo: ActorRef<Reception.Listing<Guest>>,
        timeout: Duration
    ) where Guest: ReceptionistGuest
}
