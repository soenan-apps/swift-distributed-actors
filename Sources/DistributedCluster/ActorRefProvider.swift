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

import DistributedActorsConcurrencyHelpers

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: ActorRefProvider

/// `ActorRefProvider`s are those which both create and resolve actor references.
internal protocol ActorRefProvider: ActorTreeTraversable {
    /// Path of the root guardian actor for this part of the actor tree.
    var rootAddress: ActorID { get }

    /// Spawn an actor with the passed in [Behavior] and return its [ActorRef].
    ///
    /// The returned actor ref is immediately valid and may have messages sent to.
    ///
    /// ### Lack of `.spawnWatch` on top level
    /// Note that it is not possible to `.spawnWatch` top level actors, since any stop would mean the system shutdown
    /// if you really want this then implement your own top actor to spawn children. It is possible however to use
    /// `.supervision(strategy: .escalate))` as failures bubbling up through the system may indeed be a reason to
    /// terminate.
    func spawn<Message>(
        system: ClusterSystem,
        configuration: (behavior: Behavior<Message>, props: Props),
        id: ActorID,
        dispatcher: MessageDispatcher,
        startImmediately: Bool
    ) throws -> ActorRef<Message>
    where Message: Codable

    /// Stops all actors created by this `ActorRefProvider` and blocks until they have all stopped.
    func stopAll()
}
