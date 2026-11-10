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

/// A receptionist is a system actor that allows users to register actors under
/// a key to make them available to other parts of the system, without having to
/// share a reference with that specific part directly.
///
/// There are different reasons for using the receptionist over direct sharing
/// of references, e.g. parts of the system can be brought up independently and
/// then lookup the reference of another part once it's ready, or subscribe to
/// be notified once the other part has registered.
///
/// Actors usually register themselves with the receptionist as part of their setup process.
public protocol DistributedReceptionist: DistributedActor {
    /// Registers passed in distributed actor in the systems receptionist with given id.
    ///
    /// - Parameters:
    ///   - guest: the actor to register with the receptionist.
    ///   - key: key identifier. E.g. when aiming to register all instances of "Sensor" in the same group, the
    ///   recommended id is "all/sensors".
    func checkIn<Guest>(
        _ guest: Guest,
        with key: DistributedReception.Key<Guest>
    ) async where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem

    func checkIn<Guest>(
        _ guest: Guest
    ) async where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem

    /// Returns a "listing" asynchronous sequence which will emit actor references,
    /// for every distributed actor that the receptionist discovers for the specific key.
    ///
    /// It emits both values for already existing, checked-in before the listing was created,
    /// actors; as well as new actors which are checked-in while the listing was already subscribed to.
    func listing<Guest>(
        of key: DistributedReception.Key<Guest>,
        file: String,
        line: UInt
    ) async -> DistributedReception.GuestListing<Guest>
    where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem

    /// Perform a *single* lookup for a distributed actor identified by the passed in `key`.
    ///
    /// - Parameters:
    ///   - key: selects which actors we are interested in.
    func lookup<Guest>(_ key: DistributedReception.Key<Guest>) async -> Set<Guest>
    where Guest: DistributedActor, Guest.ActorSystem == ClusterSystem
}

extension DistributedReception {
    /// 登録済みアクターと後続の新規登録を順に通知する非同期列。
    public struct GuestListing<Guest: DistributedActor>: AsyncSequence, Sendable
    where Guest.ActorSystem == ClusterSystem {
        internal let receptionist: OpLogDistributedReceptionist
        internal let key: DistributedReception.Key<Guest>

        // Location where the subscription was created
        internal let file: String
        internal let line: UInt

        public func makeAsyncIterator() -> DistributedReceptionIterator<Guest> {
            DistributedReceptionIterator(
                receptionist: self.receptionist,
                key: self.key,
                file: self.file,
                line: self.line
            )
        }
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
