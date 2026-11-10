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

internal final class DistributedReceptionistStorage {
    internal typealias ReceptionistOp = OpLogDistributedReceptionist.ReceptionistOp

    internal struct RefMappingRemovalResult {
        /// The (now removed) ref was registered under the following keys
        internal let registeredUnderKeys: Set<AnyDistributedReceptionKey>
    }
    internal struct PrunedNodeDirective {
        internal var changed: [AnyDistributedReceptionKey: Set<DistributedListingSubscription>] = [:]

        internal var keys: Dictionary<AnyDistributedReceptionKey, Set<DistributedListingSubscription>>.Keys {
            self.changed.keys
        }

        internal func peersToNotify(_ key: AnyDistributedReceptionKey) -> Set<DistributedListingSubscription> {
            self.changed[key] ?? []
        }
    }

    internal var registrationsByKey: [AnyDistributedReceptionKey: OrderedSet<VersionedRegistration>] = [:]
    internal var subscriptionsByKey: [AnyDistributedReceptionKey: Set<DistributedListingSubscription>] = [:]

    /// Per (receptionist) node mapping of which keys are presently known to this receptionist on the given node.
    /// This is used to perform quicker cleanups upon a node/receptionist crashing, and thus all existing references
    /// on that node should be removed from our storage.
    private var registeredKeysByNode: [Cluster.Node: Set<AnyDistributedReceptionKey>] = [:]

    /// Allows for reverse lookups, when an actor terminates, we know from which registrations to remove it from.
    internal var keysByActorID: [ClusterSystem.ActorID: Set<AnyDistributedReceptionKey>] = [:]

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Registrations

    /// This function ONLY operates on `.register` operations, and fails otherwise.
    ///
    /// - returns: `true` if the value was a newly inserted value, `false` otherwise
    internal func addRegistration<Guest>(
        sequenced: OpLog<ReceptionistOp>.SequencedOp,
        key: AnyDistributedReceptionKey,
        guest: Guest
    ) -> Bool
    where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {
        guard sequenced.operation.isRegister else {
            fatalError("\(#function) can only be called with .register operations, was: \(sequenced)")
        }

        self.addGuestKeyMapping(identity: guest.id, key: key)
        self.storeRegistrationNodeRelation(key: key, node: guest.id.node)

        let versionedRegistration: VersionedRegistration = VersionedRegistration(
            remoteOpSeqNr: sequenced.sequenceRange.max,
            actor: guest.asAnyDistributedActor
        )
        return self.addTo(dict: &self.registrationsByKey, key: key, value: versionedRegistration)
    }

    internal func removeRegistration<Guest>(
        key: AnyDistributedReceptionKey,
        guest: Guest
    ) -> OrderedSet<VersionedRegistration>
    where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem {

        _ = self.removeFromKeyMappings(guest.id)

        let versionedRegistration: VersionedRegistration = VersionedRegistration(
            forRemovalOf: guest.id
        )
        return self.removeFrom(dict: &self.registrationsByKey, key: key, value: versionedRegistration)
    }

    internal func registrations(forKey key: AnyDistributedReceptionKey) -> OrderedSet<VersionedRegistration> {
        self.registrationsByKey[key] ?? []
    }

    private func storeRegistrationNodeRelation(key: AnyDistributedReceptionKey, node: Cluster.Node) {
        self.registeredKeysByNode[node, default: []].insert(key)
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Subscriptions

    internal func addSubscription(
        key: AnyDistributedReceptionKey, subscription: DistributedListingSubscription
    ) -> Bool {
        self.addTo(dict: &self.subscriptionsByKey, key: key, value: subscription)
    }

    @discardableResult
    internal func removeSubscription(
        key: AnyDistributedReceptionKey,
        subscription: DistributedListingSubscription
    ) -> Set<DistributedListingSubscription> {
        self.removeFrom(dict: &self.subscriptionsByKey, key: key, value: subscription)
    }

    internal func subscriptions(forKey key: AnyDistributedReceptionKey) -> Set<DistributedListingSubscription> {
        self.subscriptionsByKey[key] ?? []
    }

    internal func removeFromKeyMappings(_ id: ActorID) -> RefMappingRemovalResult {
        guard let associatedKeys = self.keysByActorID.removeValue(forKey: id) else {
            // was not registered under any keys before
            return RefMappingRemovalResult(registeredUnderKeys: [])
        }

        var registeredKeys: Set<AnyDistributedReceptionKey> = []
        for key in associatedKeys
        where self.registrationsByKey[key]?.remove(.init(forRemovalOf: id)) != nil {
            _ = registeredKeys.insert(key)
        }

        return RefMappingRemovalResult(registeredUnderKeys: registeredKeys)
    }

    /// Prunes any registrations and subscriptions of the presence of any actors on the passed in `node`.
    ///
    /// - Returns: A result containing all keys which were changed by this operation (which previously contained nodes
    /// on this node),
    ///   as well as which local subscribers we need to notify about the change, even if _now_ they do not subscribe to
    ///   anything anymore
    ///   (as they only were interested on things on the now-removed node). This allows us to eagerly and "in batch"
    ///   give them a listing update
    ///   *once* with all the remote actors removed, rather than trickling in the changes to the Listing one by one (as
    ///   it would be the case
    ///   if we waited for Terminated signals to trickle in and handle these removals one by one then).
    internal func pruneNode(_ node: Cluster.Node) -> PrunedNodeDirective {
        let prune: PrunedNodeDirective = PrunedNodeDirective()

        guard let keys = self.registeredKeysByNode[node] else {
            // no keys were related to this node, we should have nothing to clean-up here
            return prune
        }

        // for every key that was related to the now terminated node
        for key in keys {
            // 1) we remove any registrations that it hosted
            let registrations: OrderedSet<VersionedRegistration> =
                self.registrationsByKey.removeValue(forKey: key) ?? []
            let remainingRegistrations: OrderedSet<VersionedRegistration> = registrations.filtering { registration in
                registration.actorID.node != node
            }
            if !remainingRegistrations.isEmpty {
                self.registrationsByKey[key] = remainingRegistrations
            }
        }

        return prune
    }

    /// - returns: `true` if the value was a newly inserted value, `false` otherwise
    private func addTo<Value: Hashable>(
        dict: inout [AnyDistributedReceptionKey: OrderedSet<Value>],
        key: AnyDistributedReceptionKey,
        value: Value
    ) -> Bool {
        guard !(dict[key]?.contains(value) ?? false) else {
            return false
        }

        dict[key, default: []].append(value)
        return true
    }

    /// - returns: `true` if the value was a newly inserted value, `false` otherwise
    private func addTo<Value: Hashable>(
        dict: inout [AnyDistributedReceptionKey: Set<Value>],
        key: AnyDistributedReceptionKey,
        value: Value
    ) -> Bool {
        guard !(dict[key]?.contains(value) ?? false) else {
            return false
        }

        dict[key, default: []].insert(value)
        return true
    }

    private func removeFrom<Value: Hashable>(
        dict: inout [AnyDistributedReceptionKey: OrderedSet<Value>],
        key: AnyDistributedReceptionKey,
        value: Value
    ) -> OrderedSet<Value> {
        if dict[key]?.remove(value) != nil, dict[key]?.isEmpty ?? false {
            dict.removeValue(forKey: key)
        }

        return dict[key] ?? []
    }

    private func removeFrom<Value: Hashable>(
        dict: inout [AnyDistributedReceptionKey: Set<Value>],
        key: AnyDistributedReceptionKey,
        value: Value
    ) -> Set<Value> {
        if dict[key]?.remove(value) != nil, dict[key]?.isEmpty ?? false {
            dict.removeValue(forKey: key)
        }

        return dict[key] ?? []
    }

    /// Remember that this guest did register itself under this key
    private func addGuestKeyMapping(identity: ClusterSystem.ActorID, key: AnyDistributedReceptionKey) {
        self.keysByActorID[identity, default: []].insert(key)
    }
}
