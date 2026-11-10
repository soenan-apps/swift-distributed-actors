import Distributed

extension Reception.Listing where Guest: ReceivesMessages {
    /// Retrieve all listed actor references, mapping them to their appropriate type.
    /// Note that this operation is lazy and has to iterate over all the actors when performing the
    /// iteration.
    public var refs: LazyMapSequence<Set<AddressableActorRef>, ActorRef<Guest.Message>> {
        self.underlying.lazy.map { self.key.unsafeAsActorRef($0) }
    }

    /// Returns the first listed actor, if the listing is nonempty.
    public var first: ActorRef<Guest.Message>? {
        self.underlying.first.map { addressable in
            self.key.unsafeAsActorRef(addressable)
        }
    }

    /// Returns the first listed actor whose identifier satisfies `matches`.
    public func first(where matches: (ActorID) -> Bool) -> ActorRef<Guest.Message>? {
        self.underlying.first { addressable in
            let ref: ActorRef<Guest.Message> = self.key.unsafeAsActorRef(addressable)
            return matches(ref.id)
        }.map { addressable in
            self.key.unsafeAsActorRef(addressable)
        }
    }

    /// Returns the first actor from the listing whose name matches the passed in `name` parameter.
    ///
    /// Special handling is applied to message adapters (e.g. `/uses/example/two/$messageAdapter` in which case the last
    /// segment is ignored).
    public func first(named name: String) -> ActorRef<Guest.Message>? {
        self.underlying.first { addressable in
            addressable.path.name == name
                || (addressable.path.segments.last?.value == "$messageAdapter"
                    && addressable.path.segments.dropLast(1).last?.value == name)
        }.map { addressable in
            self.key.unsafeAsActorRef(addressable)
        }
    }
}
