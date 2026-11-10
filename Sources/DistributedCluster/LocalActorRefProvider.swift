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

internal struct LocalActorRefProvider: ActorRefProvider {
    private let root: Guardian

    internal var rootAddress: ActorID {
        self.root.id
    }

    internal init(root: Guardian) {
        self.root = root
    }

    internal func spawn<Message>(
        system: ClusterSystem,
        configuration: (behavior: Behavior<Message>, props: Props),
        id: ActorID,
        dispatcher: MessageDispatcher,
        startImmediately: Bool
    ) throws -> ActorRef<Message>
    where Message: Codable {
        try self.root.makeChild(path: id.path) {
            // the cell that holds the actual "actor", though one could say the cell *is* the actor...
            let actor: ActorShell<Message> = ActorShell(
                system: system,
                parent: AddressableActorRef(root.ref),
                behavior: configuration.behavior,
                id: id,
                props: configuration.props,
                dispatcher: dispatcher
            )

            let cell: ActorCell<Message> = actor.actorCell

            if startImmediately {
                cell.sendSystemMessage(.start)
            } else {
                // If the start is delayed, we need to enqueue the `.start` message
                // without actually scheduling it to run. This ensures that `.start`
                // will still be the first message in the mailbox and also that
                // enqueueing more messages will not schedule the actor prematurely.
                cell.mailbox.enqueueStart()
            }

            return actor
        }
    }

    internal func stopAll() {
        self.root.stopAllAwait()
    }

    internal func traverse<T>(
        context: TraversalContext<T>,
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        self.root.traverse(context: context.deeper, visit)
    }

    internal func resolve<Message>(context: ResolveContext<Message>) -> ActorRef<Message> {
        self.root.resolve(context: context)
    }

    internal func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef {
        self.root.resolveUntyped(context: context)
    }
}
