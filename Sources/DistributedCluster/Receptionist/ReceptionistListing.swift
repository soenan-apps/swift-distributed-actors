import Distributed

internal protocol ReceptionistListing: AnyReceptionistListing, Equatable {
    associatedtype Message: Codable

    var refs: Set<ActorRef<Message>> { get }
}

extension ReceptionistListing {
    internal var refsAsAnyHashable: AnyHashable {
        AnyHashable(self.refs)
    }
}
