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

import Dispatch
import Logging

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: ActorRefFactory

/// Public but not intended for user-extension.
///
/// An `ActorRefFactory` is able to create ("spawn") new actors and return `ActorRef` instances for them.
/// Only the `ClusterSystem`, `ActorContext` and potentially testing facilities can ever expose this ability.
public protocol ActorRefFactory {
    /// Spawn an actor with the given `name`, optional `props` and `behavior`.
    ///
    /// ### Naming
    /// `ActorNaming` is used to determine the actors real name upon spawning;
    /// The owning `ActorContext` or `ClusterSystem` can assign a name sequentially or by another naming scheme.
    ///
    /// ### Actor Reference
    /// Discarding the returned reference means that there MAY be no longer a way to communicate with the spawned actor.
    /// Only discard references if the actor performs independent work or can be discovered by other means.
    ///
    /// ### Lifecycle
    /// Actors remain alive until they are explicitly stopped (or crash).
    /// Reference counting does not control their lifecycle; losing references does not stop an actor.
    ///
    /// - Parameters:
    ///   - naming: determines the name of the spawned actor.
    ///     A string literal selects unique naming and can throw if the name is already used.
    ///     See also `ActorNaming` on details on other naming strategies (such as `.anonymous`).
    ///   - props: properties configuring failure handling and execution semantics.
    ///   - behavior: the `Behavior` of the actor to be spawned.
    /// - Returns: `ActorRef` for the spawned actor.
    /// - Throws: When a unique name is already used in the actor's namespace.
    @discardableResult
    func spawn<Message>(
        _ naming: ActorNaming,
        _ behavior: Behavior<Message>,
        props: Props,
        file: String,
        line: UInt
    ) throws -> ActorRef<Message> where Message: Codable
}
