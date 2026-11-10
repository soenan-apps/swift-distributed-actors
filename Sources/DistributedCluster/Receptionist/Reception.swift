// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Reception

/// Namespace for public messages related to the Receptionist.
public enum Reception {

    /// Used to register and lookup actors in the receptionist.
    /// The key is a combination the Guest's type and an identifier to identify sub-groups of actors of that type.
    ///
    /// The id defaults to "*" which can be used "all actors of that type" (if and only if they registered using this
    /// key,
    /// actors which do not opt-into discovery by registering themselves WILL NOT be discovered using this, or any
    /// other, key).
    public struct Key<Guest: ReceptionistGuest>: ReceptionKeyProtocol, Codable,
        ExpressibleByStringLiteral, ExpressibleByStringInterpolation,
        CustomStringConvertible {
        internal let id: String
        internal var guestType: Any.Type {
            Guest.self
        }

        internal var asAnyKey: AnyReceptionKey {
            AnyReceptionKey(self)
        }

        public var description: String {
            "Reception.Key<\(Guest.self)>(id: \(self.id))"
        }

        public init(_: Guest.Type = Guest.self, id: String = "*") {
            self.id = id
        }

        public init(stringLiteral value: StringLiteralType) {
            self.id = value
        }

        internal func unsafeAsActorRef(_ addressable: AddressableActorRef) -> ActorRef<Guest.Message> {
            if addressable.isRemote() {
                let remotePersonality: RemoteClusterActorPersonality<Guest.Message> =
                    addressable.ref.unsafeGetRemotePersonality(Guest.Message.self)
                return ActorRef(.remote(remotePersonality))
            }
            guard let ref = addressable.ref as? ActorRef<Guest.Message> else {
                fatalError("Type mismatch, expected: [\(String(reflecting: Guest.self))] got [\(addressable)]")
            }

            return ref
        }

        internal func resolve(system: ClusterSystem, id: ActorID) -> AddressableActorRef {
            let ref: ActorRef<Guest.Message> = system.resolve(context: ResolveContext(id: id, system: system))
            return ref.asAddressable
        }
    }
    /// Response to `Lookup` and `Subscribe` requests.
    /// A listing MAY be empty.
    public struct Listing<Guest: ReceptionistGuest>: Equatable, CustomStringConvertible {
        internal let underlying: Set<AddressableActorRef>
        internal let key: Reception.Key<Guest>

        /// Efficient way to check if a listing is empty.
        public var isEmpty: Bool {
            self.underlying.isEmpty
        }

        /// Efficient way to check check the count of listed actors.
        public var count: Int {
            self.underlying.count
        }

        public var description: String {
            "Reception.Listing<\(Guest.self)>(\(self.underlying.map(\.id)))"
        }

        internal init(refs: Set<AddressableActorRef>, key: Reception.Key<Guest>) {
            self.underlying = refs
            self.key = key
        }

        public static func == (lhs: Listing<Guest>, rhs: Listing<Guest>) -> Bool {
            lhs.underlying == rhs.underlying
        }
    }
    /// Response to a `Register` message
    public final class Registered<Guest: ReceptionistGuest>: NotActuallyCodableMessage,
        CustomStringConvertible {
        internal let guest: Guest
        public let key: Reception.Key<Guest>

        public var description: String {
            "Reception.Registered(guest: \(self.guest), key: \(self.key))"
        }

        public init(_ guest: Guest, key: Reception.Key<Guest>) {
            self.guest = guest
            self.key = key
        }
    }
}
