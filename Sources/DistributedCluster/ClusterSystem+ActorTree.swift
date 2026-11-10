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

extension ClusterSystem: ActorTreeTraversable {
    /// Prints Actor hierarchy as a "tree".
    ///
    /// Note that the printout is NOT a "snapshot" of a systems state, and therefore may print actors which by the time
    /// the print completes already have terminated, or may not print actors which started just after a visit at
    /// certain parent.
    internal func printTree() {
        self.traverseAllVoid { context, ref in
            print(
                """
                \(currentPThreadThreadID()): \(String(repeating: "  ", count: context.depth))- \
                /\(ref.id.name) - \(ref) @ incarnation:\(ref.id.incarnation)
                """
            )
            return .continue
        }
    }

    internal func treeString() -> String {
        var ids: [String] = [String]()
        self.traverseAllVoid { _, ref in
            ids.append("\(ref.id.detailedDescription)")
            return .continue
        }
        return ids.joined(separator: "\n")
    }

    internal func traverse<T>(
        context: TraversalContext<T>,
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        let systemTraversed: TraversalResult<T> = self.systemProvider.traverse(context: context, visit)

        switch systemTraversed {
        case .completed:
            return self.userProvider.traverse(context: context, visit)

        case .result(let result):
            var accumulatedContext: TraversalContext<T> = context
            accumulatedContext.accumulated.append(result)
            return self.userProvider.traverse(context: accumulatedContext, visit)

        case .results(let results):
            var accumulatedContext: TraversalContext<T> = context
            accumulatedContext.accumulated.append(contentsOf: results)
            return self.userProvider.traverse(context: accumulatedContext, visit)

        case .failed(let err):
            return .failed(err)  // short circuit
        }
    }

    internal func traverseAll<T>(
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        let context: TraversalContext<T> = TraversalContext<T>()
        return self.traverse(context: context, visit)
    }

    @discardableResult
    internal func traverseAllVoid(
        _ visit: (TraversalContext<Void>, AddressableActorRef) -> TraversalDirective<Void>
    ) -> TraversalResult<Void> {
        self.traverseAll(visit)
    }

    /// INTERNAL API: Not intended to be used by end users.
    internal func resolve<Message: Codable>(context: ResolveContext<Message>) -> ActorRef<Message> {
        do {
            try context.system.serialization.ensureSerializer(Message.self)
        } catch {
            return context.personalDeadLetters
        }
        guard let selector = context.selectorSegments.first else {
            return context.personalDeadLetters
        }

        // definitely a local ref, has no `address.node`
        switch selector.value {
        case "system":
            return self.systemProvider.resolve(context: context)

        case "user":
            return self.userProvider.resolve(context: context)

        case "dead":
            return context.personalDeadLetters

        default:
            fatalError("Found unrecognized root. Only /system and /user are supported so far. Was: \(selector)")
        }
    }

    public func resolveUntyped(id: ActorID) -> AddressableActorRef {
        self.resolveUntyped(context: .init(id: id, system: self))
    }

    internal func resolveStub(id: ActorID) -> StubDistributedActor {
        do {
            return try StubDistributedActor.resolve(id: id, using: self)
        } catch {
            fatalError(
                """
                Failed to resolve a \(StubDistributedActor.self) for \(id); \
                This operation is expected to always succeed
                """
            )
        }
    }

    internal func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef {
        guard let selector = context.selectorSegments.first else {
            return context.personalDeadLetters.asAddressable
        }

        // definitely a local ref, has no `address.node`
        switch selector.value {
        case "system":
            return self.systemProvider.resolveUntyped(context: context)

        case "user":
            return self.userProvider.resolveUntyped(context: context)

        case "dead":
            return context.system.deadLetters.asAddressable

        default:
            fatalError("Found unrecognized root. Only /system and /user are supported so far. Was: \(selector)")
        }
    }
}
