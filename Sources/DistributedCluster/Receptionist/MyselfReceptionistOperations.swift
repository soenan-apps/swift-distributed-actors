import Foundation

internal protocol MyselfReceptionistOperations: ReceptionistOperations {
    associatedtype Message: Codable
    associatedtype Myself: ReceptionistGuest

    var myself: Myself { get }
    var underlyingContext: ActorContext<Message> { get }

    /// Registers `myself` in the systems receptionist with given key.
    @discardableResult
    func registerMyself(
        with key: Reception.Key<Myself>,
        replyTo: ActorRef<Reception.Registered<Myself>>?
    ) -> Reception.Key<Myself>

    /// Subscribe to actors registering under given `key`.
    ///
    /// A new `Reception.Listing<Guest>` is emitted whenever new actors join (or leave) the reception, and the
    /// `onListingChange` is then
    /// invoked on the actors context.
    ///
    /// Current Limitation: Only ONE (the most recently set using this API) `onListingChange` for a given `key` is going
    /// to be executed.
    /// This is done to avoid growing the number of callbacks infinitely, in case one would continuously invoke this API
    /// in every actorable call.
    ///
    /// - Parameters:
    ///   - key: selects which actors we are interested in.
    ///   - callback: invoked whenever actors join/leave the reception or when they terminate.
    ///               The invocation is made on the owning actor's context, meaning that it is safe to mutate actor
    ///               state from the callback.
    func subscribeMyself<Guest>(
        to key: Reception.Key<Guest>,
        subReceive callback: @escaping (Reception.Listing<Guest>) -> Void
    ) where Guest: ReceptionistGuest

}

extension MyselfReceptionistOperations {
    @inlinable
    @discardableResult
    internal func registerMyself(
        with key: Reception.Key<Myself>,
        replyTo: ActorRef<Reception.Registered<Myself>>? = nil
    ) -> Reception.Key<Myself> {
        self.register(self.myself, with: key, replyTo: replyTo)
        return key
    }

    @inlinable
    internal func subscribeMyself<Guest>(
        to key: Reception.Key<Guest>,
        subReceive callback: @escaping (Reception.Listing<Guest>) -> Void
    ) where Guest: ReceptionistGuest {
        let subReceiveStringID: String = "subscribe-\(Guest.self)"
        let id: SubReceiveId<Reception.Listing<Guest>> = .init(id: subReceiveStringID)
        let subRef: ActorRef<Reception.Listing<Guest>> = self.underlyingContext
            .subReceive(id, Reception.Listing<Guest>.self) { listing in
                callback(listing)
            }

        self.underlyingContext.receptionist.subscribe(subRef, to: key)
    }

    /// Subscribe this actor to actors registering under the given key.
    /// A new listing is emitted whenever actors join or leave the reception.
    ///
    /// - SeeAlso: `subscribeMyself(to:subReceive:)`
    @inlinable
    internal func subscribeMyself<Guest>(
        to key: Reception.Key<Guest>
    ) where Guest: ReceptionistGuest, Myself.Message == Reception.Listing<Guest> {
        self.subscribe(self.myself.ref, to: key)
    }
}
