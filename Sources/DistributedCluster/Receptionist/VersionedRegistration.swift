// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed
import Logging
import OrderedCollections

/// Represents a registration of an actor with its (local) receptionist,
/// at the version represented by the `(seqNr, .node(actor.<address>.node))`.
///
/// This allows a local subscriber to definitely compare a registration with its "already seen"
/// version vector (that contains versions for every node it is receiving updates from),
/// and only emit those to the user-facing stream which have not been observed yet.
internal struct VersionedRegistration: Hashable {
    internal let version: VersionVector
    internal let actorID: ClusterSystem.ActorID

    internal init(remoteOpSeqNr: UInt64, actor: AnyDistributedActor) {
        self.version = VersionVector(remoteOpSeqNr, at: .node(actor.id.node))
        self.actorID = actor.id
    }

    internal init(forRemovalOf actorID: ActorID) {
        self.version = .empty
        self.actorID = actorID
    }

    internal static func == (lhs: Self, rhs: Self) -> Bool {
        if lhs.actorID != rhs.actorID {
            return false
        }
        return true
    }

    internal func hash(into hasher: inout Hasher) {
        hasher.combine(self.actorID)
    }

}
