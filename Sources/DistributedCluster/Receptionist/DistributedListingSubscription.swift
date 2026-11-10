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

/// Represents a local subscription (for `receptionist.subscribe`) for a specific key.
internal final class DistributedListingSubscription: Hashable, @unchecked Sendable, CustomStringConvertible {
    internal let subscriptionID: ObjectIdentifier
    internal let key: AnyDistributedReceptionKey

    #if DEBUG
    internal let file: String
    internal let line: UInt
    #endif

    /// Offer a new listing to the subscription stream
    private let onNext: @Sendable (ClusterSystem.ActorID) -> Void

    /// We very carefully only modify this from the owning actor (receptionist).
    internal var seenActorRegistrations: VersionVector

    internal var description: String {
        var string: String = "DistributedListingSubscription(subscriptionID: \(subscriptionID), key: \(key), "
            + ", seenActorRegistrations: \(seenActorRegistrations)"
        #if DEBUG
        string += ", at: \(self.file):\(self.line)"
        #endif
        string += ")"
        return string
    }

    internal init(
        subscriptionID: ObjectIdentifier,
        file: String,
        line: UInt,
        key: AnyDistributedReceptionKey,
        onNext: @escaping @Sendable (ClusterSystem.ActorID) -> Void
    ) {
        self.subscriptionID = subscriptionID
        self.key = key
        self.onNext = onNext
        self.seenActorRegistrations = .empty
        #if DEBUG
        self.file = file
        self.line = line
        #endif
    }

    internal static func == (lhs: DistributedListingSubscription, rhs: DistributedListingSubscription) -> Bool {
        lhs.subscriptionID == rhs.subscriptionID && lhs.key == rhs.key
    }

    /// Attempt to offer a registration to the subscriber of this stream.
    ///
    /// Since a subscription should never emit the same actor "appearing" multiple times,
    /// and each registration is unique per the origin node of the offered actor,
    /// we can check the incoming version, and if we're already "seen" it, we can
    /// safely ignore the offer.
    ///
    /// We implement this by storing a version vector that contains all nodes and versions we're
    /// getting potential offers from. Each incoming registration always has exactly one replicaID,
    /// because the changes are simply from "that node". We can merge the incoming version with out
    /// version vector, to see if it "advanced it" - if so, it must be a new registration and we have
    /// to emit the value. If it didn't advance the local "seen" version vector, it means we've already
    /// seen this actor in this specific stream, and don't need to emit it again.
    ///
    /// - Returns: true if the value was successfully offered
    internal func tryOffer(registration: VersionedRegistration) -> Bool {
        let oldSeenRegistrations: VersionVector = self.seenActorRegistrations
        self.seenActorRegistrations.merge(other: registration.version)

        switch self.seenActorRegistrations.compareTo(oldSeenRegistrations) {
        case .same:
            // the seen vector was unaffected by the merge, which means that the
            // incoming registration version was already seen, and thus we don't need to emit it again
            return false

        case .happenedAfter, .concurrent:
            // the incoming registration has not yet been seen before,
            // which means that we should emit the actor to the stream.
            self.onNext(registration.actorID)
            return true

        case .happenedBefore:
            fatalError(
                """
                It should not be possible for a *merged* version vector to be in the PAST \
                as compared with itself before the merge
                   Previously: \(oldSeenRegistrations)
                   Current: \(self.seenActorRegistrations)
                   Registration: \(registration)
                   Self: \(self)
                """
            )
        }
    }

    internal func hash(into hasher: inout Hasher) {
        hasher.combine(self.subscriptionID)
        hasher.combine(self.key)
    }

}
