// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO

/// The purpose of this cell is to allow storing cells of different types in a collection, i.e. Children
internal protocol AbstractShellProtocol: ActorTreeTraversable {
    var systemMessageReceiver: ReceivesSystemMessages { get }
    var children: Children { get set }  // lock-protected
    var asAddressable: AddressableActorRef { get }
    var metrics: ActiveActorMetrics { get }
}

extension AbstractShellProtocol {
    @inlinable internal var receivesSystemMessages: ReceivesSystemMessages {
        self.systemMessageReceiver
    }

    /// Visits this shell and its children using the supplied traversal directive.
    public func traverse<T>(
        context: TraversalContext<T>,
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        var traversalContext: TraversalContext<T> = context.deeper
        let directive: TraversalDirective<T> = visit(context, self.asAddressable)

        switch directive {
        case .continue:
            return self.children.traverse(context: traversalContext, visit)

        case .accumulateSingle(let value):
            traversalContext.accumulated.append(value)
            return self.children.traverse(context: traversalContext, visit)

        case .accumulateMany(let values):
            traversalContext.accumulated.append(contentsOf: values)
            return self.children.traverse(context: traversalContext, visit)

        case .abort(let err):
            return .failed(err)
        }
    }

    /// Resolves a typed actor reference or returns personal dead letters when it cannot be selected.
    public func resolve<Message>(context: ResolveContext<Message>) -> ActorRef<Message>
    where Message: Codable {
        let myself: ReceivesSystemMessages = self.systemMessageReceiver

        do {
            try context.system.serialization.ensureSerializer(Message.self)
        } catch {
            context.system.log.warning("Failed to ensure serializer for \(String(reflecting: Message.self))")
            return context.personalDeadLetters
        }

        guard context.selectorSegments.first != nil else {
            // no remaining selectors == we are the "selected" ref, apply uid check
            if myself.id.incarnation == context.id.incarnation {
                switch myself {
                case let resolvedActor as ActorRef<Message>:
                    return resolvedActor

                default:
                    return context.personalDeadLetters
                }
            } else {
                // the selection was indeed for this path, however we are a different incarnation (or different actor)
                return context.personalDeadLetters
            }
        }

        return self.children.resolve(context: context)
    }

    /// Resolves an addressable reference or returns personal dead letters when it cannot be selected.
    public func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef {
        guard context.selectorSegments.first != nil else {
            // no remaining selectors == we are the "selected" ref, apply uid check
            if self.systemMessageReceiver.id.incarnation == context.id.incarnation {
                return self.asAddressable
            }
            // the selection was indeed for this path, however we are a different incarnation (or different actor)
            return context.personalDeadLetters.asAddressable
        }

        return self.children.resolveUntyped(context: context)
    }
}
