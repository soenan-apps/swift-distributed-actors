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

import AsyncAlgorithms
import CoreMetrics
import Distributed
import Logging
import OrderedCollections

extension OpLogDistributedReceptionist: LifecycleWatch {
    nonisolated public func checkIn<Guest>(
        _ guest: Guest,
        with key: DistributedReception.Key<Guest>
    ) async where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        await self.whenLocal { myself in
            myself.checkInLocal(guest, with: key)
        }
    }

    nonisolated public func checkIn<Guest>(
        _ guest: Guest
    ) async where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        guard let keyID: String = guest.id.metadata.receptionID else {
            fatalError(
                """
                Attempted to \(#function) distributed actor without `@ActorID.Metadata(\\.receptionID)` set on ActorID!
                Please set the metadata during actor initialization.
                """
            )
        }
        let key: DistributedReception.Key<Guest> = DistributedReception.Key(Guest.self, id: keyID)

        await self.whenLocal { myself in
            myself.checkInLocal(guest, with: key)
        }
    }

    // 'local' implementation of checkIn
    internal func checkInLocal<Guest>(
        _ guest: Guest,
        with key: DistributedReception.Key<Guest>
    ) where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        let guestID: ID = guest.id
        let anyKey: AnyDistributedReceptionKey = key.asAnyKey

        self.log.debug(
            "Receptionist checkIn [\(guest.id)] with key [\(anyKey)]",
            metadata: [
                "receptionist/key": "\(anyKey)",
                "receptionist/guest": "\(guest.id)",
            ]
        )

        guard guestID.isLocal || (guestID.node == actorSystem.cluster.node) else {
            self.log.warning(
                """
                Actor [\(guest.id)] attempted to checkIn under key [\(anyKey)], with NOT-local receptionist! \
                Actors MUST checkIn with their local receptionist in today's Receptionist implementation.
                """
            )
            return
        }

        let sequenced: OpLog<ReceptionistOp>.SequencedOp =
            self.addOperation(.register(key: anyKey, identity: guest.id))

        if self.storage.addRegistration(sequenced: sequenced, key: anyKey, guest: guest) {

            watchTermination(of: guest)

            self.log.debug(
                "Registered [\(guestID)] for key [\(anyKey)]",
                metadata: [
                    "receptionist/key": "\(anyKey)",
                    "receptionist/guest": "\(guestID)",
                    "receptionist/opLog/maxSeqNr": "\(self.ops.maxSeqNr)",
                    "receptionist/opLog": Logger.MetadataValue.array(
                        self.ops.ops.map { Logger.MetadataValue.string("\($0)") }
                    ),
                ]
            )

            self.ensureDelayedListingFlush(of: anyKey)
        } else {
            self.log.warning(
                "Unable to register \(guest) with receptionist, unknown identity type?",
                metadata: [
                    "guest/id": "\(guest.id)",
                    "reception/key": "\(anyKey)",
                ]
            )
        }

        // Replication of is done in periodic tics, thus we do not perform a push here.

    }

    nonisolated public func listing<Guest>(
        of key: DistributedReception.Key<Guest>,
        file: String = #fileID,
        line: UInt = #line
    ) -> DistributedReception.GuestListing<Guest>
    where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        DistributedReception.GuestListing<Guest>(receptionist: self, key: key, file: file, line: line)
    }

    nonisolated public func listing<Guest>(
        of _: Guest.Type,
        file: String = #fileID,
        line: UInt = #line
    ) -> DistributedReception.GuestListing<Guest>
    where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        DistributedReception.GuestListing<Guest>(receptionist: self, key: Key<Guest>(), file: file, line: line)
    }

    // 'local' impl for 'listing'
    internal func addSubscription(
        subscription: DistributedListingSubscription,
        file: String = #fileID,
        line: UInt = #line
    ) {
        if self.storage.addSubscription(key: subscription.key, subscription: subscription) {
            self.log.trace(
                "Subscribed async sequence to \(subscription.key)",
                metadata: [
                    "subscription/key": "\(subscription.key)",
                    "subscription/callSite": "\(file):\(line)",
                ]
            )

            // We immediately flush all already-known registrations;
            // as new ones come in, they will be reported to this subscription later on
            for alreadyRegisteredAtSubscriptionTime in self.storage.registrations(forKey: subscription.key) {
                if subscription.tryOffer(registration: alreadyRegisteredAtSubscriptionTime) {
                    self.log.debug(
                        "Offered \(alreadyRegisteredAtSubscriptionTime.actorID) to subscription \(subscription)"
                    )
                } else {
                    self.log.warning(
                        "Dropped \(alreadyRegisteredAtSubscriptionTime.actorID) on subscription \(subscription)"
                    )
                }
            }
        }
    }

    internal func cancelSubscription(
        subscription: DistributedListingSubscription
    ) {
        self.log.trace(
            "Cancel subscription [\(subscription.subscriptionID)]",
            metadata: [
                "subscription/key": "\(subscription.key)"
            ]
        )
        self.storage.removeSubscription(key: subscription.key, subscription: subscription)
    }

    nonisolated public func lookup<Guest>(_ key: DistributedReception.Key<Guest>) async -> Set<Guest>
    where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        await self.whenLocal { myself in
            myself.lookupLocal(key)
        } ?? []
    }

    internal func lookupLocal<Guest>(_ key: DistributedReception.Key<Guest>) -> Set<Guest>
    where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        let registrations: OrderedSet<VersionedRegistration> = self.storage.registrations(forKey: key.asAnyKey)
        guard !registrations.isEmpty else {
            return []
        }

        var guests: Set<Guest> = []
        guests.reserveCapacity(registrations.count)
        for versioned in registrations {
            do {
                let guest: Guest = try Guest.resolve(id: versioned.actorID, using: self.actorSystem)
                guests.insert(guest)
            } catch is DeadLetterError {
                // This just means that this `lookup` arrived before the `terminated` of this
                // specific actor as it terminated.
                // This specific actor is already dead, so there's no need to emit it in our listing.
                //
                // The terminated arrives asynchronously and will arrive a bit later;
                // We can also just cause the terminated eagerly over here
                self.actorTerminated(id: versioned.actorID)
                continue
            } catch {
                self.actorSystem.log.debug(
                    "Failed to resolve guest for listing key \(key)",
                    metadata: [
                        "actor/id": "\(versioned.actorID)",
                        "actor/type": "\(Guest.self)",
                        "error": "\(error)",
                    ]
                )
            }
        }

        return guests
    }
}
