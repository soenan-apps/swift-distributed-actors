// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Plugin protocol

/// Lifecycle shared by installed cluster plugins.
public protocol AnyPlugin {
    /// Starts the plugin.
    func start(_ system: ClusterSystem) async throws

    /// Stops the plugin.
    func stop(_ system: ClusterSystem) async
}

/// Kind of `ClusterSystem` plugin which will be invoked during an actor's `actorReady`
/// and `resignID` lifecycle hooks.
///
/// The ready hook is allowed to modify the ID, e.g. by adding additional metadata to it.
/// The plugin should carefully manage retaining actors and document if it does have strong references to them,
/// and how end-users should go about releasing them.
public protocol ActorLifecyclePlugin: Plugin {
    func onActorReady<Act: DistributedActor>(_ actor: Act) where Act: DistributedActor, Act.ID == ClusterSystem.ActorID
    func onResignID(_ id: ClusterSystem.ActorID)
}
/// A plugin provides specific features and capabilities (e.g., singleton) to a `ClusterSystem`.
public protocol Plugin: AnyPlugin {
    typealias Key = PluginKey<Self>

    /// The plugin's unique identifier
    var key: Key { get }
}
