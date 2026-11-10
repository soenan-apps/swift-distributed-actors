// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Logging

/// A receptionist is an actor that allows users to register actors under
/// a key to make them available to other parts of the system, without having to
/// share a reference with that specific part directly. There are different reasons
/// for using the receptionist over direct sharing of references, e.g. parts of
/// the system can be brought up independently and then lookup the reference of
/// another part once it's ready, or subscribe to be notified once the other
/// part has registered.
///
/// Actors usually register themselves with the receptionist as part of their initializer.
public enum Receptionist {
    /// 登録・検出対象のメッセージ型。
    public typealias Message = ReceptionistMessage

    /// INTERNAL API
    /// When sent to receptionist will register the specified `ActorRef` under the given `Reception.Key`
    public class Register<Guest: ReceptionistGuest>: AnyReceptionRegistration, @unchecked Sendable {
        public let guest: Guest
        public let key: Reception.Key<Guest>
        public let replyTo: ActorRef<Reception.Registered<Guest>>?

        override internal var addressableActorRef: AddressableActorRef {
            AddressableActorRef(self.guest.ref)
        }

        override internal var erasedKey: AnyReceptionKey {
            self.key.asAnyKey
        }

        override public var description: String {
            "Register(ref: \(self.guest), key: \(self.key), replyTo: \(String(reflecting: self.replyTo))"
        }

        public init(
            _ ref: Guest,
            key: Reception.Key<Guest>,
            replyTo: ActorRef<Reception.Registered<Guest>>? = nil
        ) {
            self.guest = ref
            self.key = key
            self.replyTo = replyTo
            super.init()
        }

        public required init(from _: Decoder) throws {
            throw SerializationError(.nonTransportableMessage(type: ""))
        }

        override internal func replyRegistered() {
            self.replyTo?.tell(Reception.Registered(self.guest, key: self.key))
        }
    }

    /// INTERNAL API
    /// Used to lookup `ActorRef`s for the given `Reception.Key`
    public class Lookup<Guest: ReceptionistGuest>: ReceptionLookup, ListingRequest,
        CustomStringConvertible, @unchecked Sendable {
        public let key: Reception.Key<Guest>
        public let subscriber: ActorRef<Reception.Listing<Guest>>

        public var description: String {
            "Receptionist.Lookup(key: \(self.key), replyTo: \(self.subscriber))"
        }

        public init(key: Reception.Key<Guest>, replyTo: ActorRef<Reception.Listing<Guest>>) {
            self.key = key
            self.subscriber = replyTo
            super.init(erasedKey: key.asAnyKey)
        }

        internal required init(from _: Decoder) throws {
            throw SerializationError(.nonTransportableMessage(type: "\(Self.self)"))
        }

        override internal func replyWith(_ refs: Set<AddressableActorRef>) {
            self.subscriber.tell(Reception.Listing(refs: refs, key: self.key))
        }
    }

    /// INTERNAL API
    /// Subscribe to periodic updates of the specified key
    public class Subscribe<Guest: ReceptionistGuest>: ReceptionSubscription, ListingRequest,
        CustomStringConvertible, @unchecked Sendable {
        public let key: Reception.Key<Guest>
        public let subscriber: ActorRef<Reception.Listing<Guest>>

        override internal var erasedKey: AnyReceptionKey {
            self.key.asAnyKey
        }

        override internal var boxedSubscription: AnySubscribe {
            AnySubscribe(subscribe: self)
        }

        override internal var addressableActorRef: AddressableActorRef {
            self.subscriber.asAddressable
        }

        public var description: String {
            "Receptionist.Subscribe(key: \(self.key), replyTo: \(self.subscriber))"
        }

        public init(key: Reception.Key<Guest>, subscriber: ActorRef<Reception.Listing<Guest>>) {
            self.key = key
            self.subscriber = subscriber
            super.init()
        }

        public required init(from _: Decoder) throws {
            throw SerializationError(.nonTransportableMessage(type: "\(Self.self)"))
        }

        internal func replyWith(_ refs: Set<AddressableActorRef>) {
            self.subscriber.tell(Reception.Listing(refs: refs, key: self.key))
        }
    }

    // Receptionist messages are a bit special. Technically we CAN allow sending them over to remotes
    // but we do not today. Generally though, for example registering with a remote's receptionist is a "bad idea"™
    // it is more efficient to register on the local one, so what we could do, is when sending to a remote receptionist,
    // is to detect that and rather send to the local one.

    internal static let naming: ActorNaming = .unique("receptionist-ref")

}

extension ActorPath {
    /// The ActorRef<> receptionist, to be eventually removed.
    internal static let actorRefReceptionist: ActorPath =
        ActorPath.systemRoot.appending(segment: .actorRefReceptionist)

    /// The 'distributed actor' receptionist's well-known path.
    internal static let distributedActorReceptionist: ActorPath =
        ActorPath.systemRoot.appending(segment: .distributedActorReceptionist)
}

extension ActorID {
    internal enum ReceptionistType {
        case actorRefs
        case distributedActors
    }

    internal static func actorRefReceptionist(on node: Cluster.Node, for type: ReceptionistType) -> ActorID {
        switch type {
        case .actorRefs:
            return ActorPath.actorRefReceptionist.makeRemoteID(on: node, incarnation: .wellKnown)

        case .distributedActors:
            let id: ActorID = ActorPath.distributedActorReceptionist.makeRemoteID(on: node, incarnation: .wellKnown)
            id.metadata.wellKnown = ActorPath.distributedActorReceptionist.name
            return id
        }
    }
}

extension ActorRef: ReceptionistGuest {
    /// 登録対象の型付きアクター参照。
    public var ref: ActorRef<Message> { self }
}
