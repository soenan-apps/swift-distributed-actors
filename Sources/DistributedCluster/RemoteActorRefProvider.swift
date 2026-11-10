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

// consider if we need abstraction / does it cost us?
internal struct RemoteActorRefProvider: ActorRefProvider {
    private let localNode: Cluster.Node
    private let localProvider: LocalActorRefProvider

    internal let cluster: ClusterShell
    internal var rootAddress: ActorID {
        self.localProvider.rootAddress
    }
    // restructure it somehow, perhaps we dont need the full abstraction like this
    internal init(
        settings: ClusterSystemSettings,
        cluster: ClusterShell,
        localProvider: LocalActorRefProvider
    ) {
        precondition(settings.enabled, "Remote actor provider should only be used when clustering is enabled")

        self.localNode = settings.bindNode
        self.cluster = cluster
        self.localProvider = localProvider
    }
    internal func spawn<Message>(
        system: ClusterSystem,
        configuration: (behavior: Behavior<Message>, props: Props),
        id: ActorID,
        dispatcher: MessageDispatcher,
        startImmediately: Bool
    ) throws -> ActorRef<Message>
    where Message: Codable {
        // spawn is always local, thus we delegate to the underlying provider
        try self.localProvider.spawn(
            system: system,
            configuration: configuration,
            id: id,
            dispatcher: dispatcher,
            startImmediately: startImmediately
        )
    }

    internal func stopAll() {
        self.localProvider.stopAll()
    }

    internal func traverse<T>(
        context: TraversalContext<T>,
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        self.localProvider.traverse(context: context, visit)
    }
    internal func resolve<Message>(context: ResolveContext<Message>) -> ActorRef<Message> {
        switch context.id.location {
        case .local:
            return self.localProvider.resolve(context: context)

        case let .remote(node) where node == self.localNode:
            // in case we got a forwarded reference to ourselves, we can do this to serialize properly as .local

            return self.localProvider.resolve(context: context)

        case .remote:
            return self.resolveAsRemoteRef(context, remoteAddress: context.id.asRemote)
        }
    }

    internal func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef {
        if self.localNode == context.id.node {
            return self.localProvider.resolveUntyped(context: context)
        }
        return AddressableActorRef(self.resolveAsRemoteRef(context, remoteAddress: context.id.asRemote))
    }

    internal func resolveAsRemoteRef<Message>(
        _ context: ResolveContext<Message>,
        remoteAddress id: ActorID
    ) -> ActorRef<Message> {
        ActorRef(.remote(.init(shell: self.cluster, id: id, system: context.system)))
    }
}
