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

/// Traverses first one tree then the other.
/// Mostly needed since we need to expose the traversal to serialization, but we can't expose self of the actor system
/// just yet there.
@usableFromInline
internal struct CompositeActorTreeTraversable: ActorTreeTraversable {
    internal let systemTree: ActorTreeTraversable
    internal let userTree: ActorTreeTraversable

    // duplicates some logic from traverse implementation on Actor system (due to initialization dances), see if we can
    // remove the duplication of this
    // we may be able to pull this off by implementing the "root" as traversable and then we expose it to the
    // Serialization() impl
    internal func traverse<T>(
        context: TraversalContext<T>,
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        let systemTraversed: TraversalResult<T> = self.systemTree.traverse(context: context, visit)

        switch systemTraversed {
        case .completed:
            return self.userTree.traverse(context: context, visit)

        case let .result(value):
            var traversal: TraversalContext<T> = context
            traversal.accumulated.append(value)
            return self.userTree.traverse(context: traversal, visit)

        case let .results(values):
            var traversal: TraversalContext<T> = context
            traversal.accumulated.append(contentsOf: values)
            return self.userTree.traverse(context: traversal, visit)

        case let .failed(err):
            return .failed(err)  // short circuit
        }
    }

    internal func resolve<Message>(context: ResolveContext<Message>) -> ActorRef<Message> {
        guard let selector = context.selectorSegments.first else {
            return context.personalDeadLetters  // i.e. we resolved a "dead reference" as it points to nothing
        }
        switch selector.value {
        case "system":
            return self.systemTree.resolve(context: context)

        case "user":
            return self.userTree.resolve(context: context)

        case "dead":
            return context.personalDeadLetters

        default:
            fatalError("Found unrecognized root. Only /system and /user are supported so far. Was: \(selector)")
        }
    }

    internal func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef {
        guard let selector = context.selectorSegments.first else {
            return context.personalDeadLetters.asAddressable
        }
        switch selector.value {
        case "system":
            return self.systemTree.resolveUntyped(context: context)

        case "user":
            return self.userTree.resolveUntyped(context: context)

        case "dead":
            return context.personalDeadLetters.asAddressable

        default:
            fatalError("Found unrecognized root. Only /system and /user are supported so far. Was: \(selector)")
        }
    }
}
