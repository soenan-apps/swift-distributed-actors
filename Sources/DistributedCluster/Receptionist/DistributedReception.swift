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
// MARK: DistributedReception

/// Namespace for public messages related to the DistributedReceptionist.
public enum DistributedReception {

    /// Used to register and lookup actors in the receptionist.
    /// The key is a combination the Guest's type and an identifier to identify sub-groups of actors of that type.
    ///
    /// The id defaults to "*" which can be used "all actors of that type" (if and only if they registered using this
    /// key,
    /// actors which do not opt-into discovery by registering themselves WILL NOT be discovered using this, or any
    /// other, key).
    public struct Key<Guest: DistributedActor>: Codable, Sendable,
        ExpressibleByStringLiteral, ExpressibleByStringInterpolation,
        CustomStringConvertible
    where Guest.ActorSystem == ClusterSystem {
        public let id: String
        public var guestType: Any.Type {
            Guest.self
        }

        internal var asAnyKey: AnyDistributedReceptionKey {
            AnyDistributedReceptionKey(self)
        }

        public var description: String {
            "DistributedReception.Key<\(String(reflecting: Guest.self))>(id: \(self.id))"
        }

        public init(_: Guest.Type = Guest.self, id: String = "*") {
            self.id = id
        }

        public init(stringLiteral value: StringLiteralType) {
            self.id = value
        }

        internal func resolve(system: ClusterSystem, id: ActorID) -> AddressableActorRef {
            let ref: ActorRef<InvocationMessage> = system.resolve(context: ResolveContext(id: id, system: system))
            return ref.asAddressable
        }
    }
}

extension ActorMetadataKeys {
    /// Receptionist 登録に使用するメタデータキー。
    public var receptionID: Key<String> { "$receptionID" }
}

extension ActorID {
    /// Receptionist 登録IDの有無。
    public var hasReceptionID: Bool {
        self.metadata.receptionID != nil
    }
}
