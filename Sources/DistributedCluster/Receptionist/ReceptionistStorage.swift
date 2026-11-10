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

internal final class ReceptionistStorage {
    internal struct RefMappingRemovalResult {
        /// The (now removed) ref was registered under the following keys
        internal let registeredUnderKeys: Set<AnyReceptionKey>
    }
    internal struct PrunedNodeDirective {
        internal var changed: [AnyReceptionKey: Set<AnySubscribe>] = [:]

        internal var keys: Dictionary<AnyReceptionKey, Set<AnySubscribe>>.Keys {
            self.changed.keys
        }

        internal func peersToNotify(_ key: AnyReceptionKey) -> Set<AnySubscribe> {
            self.changed[key] ?? []
        }
    }

    internal var registrationsByKey: [AnyReceptionKey: Set<AddressableActorRef>] = [:]
    internal var subscriptionsByKey: [AnyReceptionKey: Set<AnySubscribe>] = [:]

    /// Per (receptionist) node mapping of which keys are presently known to this receptionist on the given node.
    /// This is used to perform quicker cleanups upon a node/receptionist crashing, and thus all existing references
    /// on that node should be removed from our storage.
    private var registeredKeysByNode: [Cluster.Node: Set<AnyReceptionKey>] = [:]

    /// Allows for reverse lookups, when an actor terminates, we know from which registrations and subscriptions to
    /// remove it from.
    internal var keysByActorID: [ActorID: Set<AnyReceptionKey>] = [:]

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Registrations

    /// - returns: `true` if the value was a newly inserted value, `false` otherwise
    internal func addRegistration(key: AnyReceptionKey, ref: AddressableActorRef) -> Bool {
        self.addRefKeyMapping(id: ref.id, key: key)
        self.storeRegistrationNodeRelation(key: key, node: ref.id.node)
        return self.addTo(dict: &self.registrationsByKey, key: key, value: ref)
    }

    internal func removeRegistration(key: AnyReceptionKey, ref: AddressableActorRef) -> Set<AddressableActorRef> {
        _ = self.removeFromKeyMappings(ref)
        return self.removeFrom(dict: &self.registrationsByKey, key: key, value: ref)
    }

    internal func registrations(forKey key: AnyReceptionKey) -> Set<AddressableActorRef> {
        self.registrationsByKey[key] ?? []
    }

    private func storeRegistrationNodeRelation(key: AnyReceptionKey, node: Cluster.Node) {
        self.registeredKeysByNode[node, default: []].insert(key)
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Subscriptions

    internal func addSubscription(key: AnyReceptionKey, subscription: AnySubscribe) -> Bool {
        self.addRefKeyMapping(id: subscription.id, key: key)
        return self.addTo(dict: &self.subscriptionsByKey, key: key, value: subscription)
    }

    @discardableResult
    internal func removeSubscription(key: AnyReceptionKey, subscription: AnySubscribe) -> Set<AnySubscribe> {
        _ = self.removeFromKeyMappings(id: subscription.id)
        return self.removeFrom(dict: &self.subscriptionsByKey, key: key, value: subscription)
    }

    internal func subscriptions(forKey key: AnyReceptionKey) -> Set<AnySubscribe> {
        self.subscriptionsByKey[key] ?? []
    }

    /// - Returns: set of keys that this actor was REGISTERED under, and thus listings associated with it should be
    /// updated
    internal func removeFromKeyMappings(id: ActorID) -> RefMappingRemovalResult {
        let equalityHackRef: ActorRef<Never> = ActorRef(.deadLetters(.init(Logger(label: ""), id: id, system: nil)))
        return self.removeFromKeyMappings(equalityHackRef.asAddressable)
    }

    /// - Returns: set of keys that this actor was REGISTERED under, and thus listings associated with it should be
    /// updated
    internal func removeFromKeyMappings(_ ref: AddressableActorRef) -> RefMappingRemovalResult {
        guard let associatedKeys = self.keysByActorID.removeValue(forKey: ref.id) else {
            return RefMappingRemovalResult(registeredUnderKeys: [])
        }

        var registeredKeys: Set<AnyReceptionKey> = []
        for key in associatedKeys {
            if self.registrationsByKey[key]?.remove(ref) != nil {
                _ = registeredKeys.insert(key)
            }
            self.subscriptionsByKey[key]?.remove(.init(id: ref.id))
        }

        return RefMappingRemovalResult(
            registeredUnderKeys: registeredKeys
        )
    }

    /// Prunes any registrations and subscriptions of the presence of any actors on the passed in `node`.
    ///
    /// - Returns: A result containing all keys which were changed by this operation (which previously contained
    /// nodes on this node),
    ///   as well as which local subscribers we need to notify about the change, even if _now_ they do not subscribe
    ///   to anything anymore
    ///   (as they only were interested on things on the now-removed node). This allows us to eagerly and "in batch"
    ///   give them a listing update
    ///   *once* with all the remote actors removed, rather than trickling in the changes to the Listing one by one
    ///   (as it would be the case
    ///   if we waited for Terminated signals to trickle in and handle these removals one by one then).
    internal func pruneNode(_ node: Cluster.Node) -> PrunedNodeDirective {
        var prune: PrunedNodeDirective = PrunedNodeDirective()

        guard let keys = self.registeredKeysByNode[node] else {
            // no keys were related to this node, we should have nothing to clean-up here
            return prune
        }

        // for every key that was related to the now terminated node
        for key in keys {
            // 1) we remove any registrations that it hosted
            let registrations: Set<AddressableActorRef> = self.registrationsByKey.removeValue(forKey: key) ?? []
            let remainingRegistrations: Set<AddressableActorRef> = registrations.filter { $0.id.node != node }
            if !remainingRegistrations.isEmpty {
                self.registrationsByKey[key] = remainingRegistrations
            }

            // 2) and remove any of our subscriptions
            let subs: Set<AnySubscribe> = self.subscriptionsByKey.removeValue(forKey: key) ?? []
            let prunedSubs: Set<AnySubscribe> = subs.filter { $0.id.node != node }
            if remainingRegistrations.count != registrations.count {
                // only if the set of registered actors for this key was actually affected by this prune
                // we want to mark it as changed and ensure we contact all of such keys subscribers about the
                // change.
                // In other words: we want to avoid pushing not-changed Listings.
                prune.changed[key] = prunedSubs
            }
            if !prunedSubs.isEmpty {
                self.subscriptionsByKey[key] = prunedSubs
            }
        }

        return prune
    }

    /// - returns: `true` if the value was a newly inserted value, `false` otherwise
    private func addTo<Value: Hashable>(
        dict: inout [AnyReceptionKey: Set<Value>],
        key: AnyReceptionKey,
        value: Value
    ) -> Bool {
        guard !(dict[key]?.contains(value) ?? false) else {
            return false
        }

        dict[key, default: []].insert(value)
        return true
    }

    private func removeFrom<Value: Hashable>(
        dict: inout [AnyReceptionKey: Set<Value>],
        key: AnyReceptionKey,
        value: Value
    ) -> Set<Value> {
        if dict[key]?.remove(value) != nil, dict[key]?.isEmpty ?? false {
            dict.removeValue(forKey: key)
        }

        return dict[key] ?? []
    }

    private func addRefKeyMapping(id: ActorID, key: AnyReceptionKey) {
        self.keysByActorID[id, default: []].insert(key)
    }
}
