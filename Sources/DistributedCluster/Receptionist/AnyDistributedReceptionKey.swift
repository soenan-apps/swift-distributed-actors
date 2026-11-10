import Distributed

internal struct AnyDistributedReceptionKey: Sendable, Codable, Hashable, CustomStringConvertible {
    internal enum CodingKeys: CodingKey {
        case id
        case guestTypeManifest
    }

    internal let id: String
    internal let guestType: Any.Type

    internal var asAnyKey: Self {
        self
    }

    internal var description: String {
        "\(Self.self)<\(reflecting: self.guestType)>(\(self.id))"
    }

    internal init<Guest>(_ key: DistributedReception.Key<Guest>) {
        self.id = key.id
        self.guestType = Guest.self
    }

    internal init(from decoder: Decoder) throws {
        guard let context = decoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(decoder, Self.self)
        }

        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)

        let guestTypeManifest: Serialization.Manifest =
            try container.decode(Serialization.Manifest.self, forKey: .guestTypeManifest)
        self.guestType = try context.summonType(from: guestTypeManifest)
    }

    internal static func == (lhs: Self, rhs: Self) -> Bool {
        if type(of: lhs) != type(of: rhs) {
            return false
        }
        if lhs.id != rhs.id {
            return false
        }
        if ObjectIdentifier(lhs.guestType) != ObjectIdentifier(rhs.guestType) {
            return false
        }
        return true
    }

    internal func resolve(system: ClusterSystem, id: ActorID) -> AddressableActorRef {
        // Since we don't have the type information here, we can't properly resolve
        // and the only safe thing to do is to return `deadLetters`.
        system.personalDeadLetters(recipient: id, type: Never.self).asAddressable
    }

    internal func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
        hasher.combine(ObjectIdentifier(self.guestType))
    }

    internal func encode(to encoder: Encoder) throws {
        guard let context = encoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(encoder, Self.self)
        }

        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.id, forKey: .id)
        let guestTypeManifest: Serialization.Manifest = try context.serialization.outboundManifest(self.guestType)
        try container.encode(guestTypeManifest, forKey: .guestTypeManifest)
    }
}
