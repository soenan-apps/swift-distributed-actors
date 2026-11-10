import Logging

extension Children: ActorTreeTraversable {
    internal func traverse<T>(
        context: TraversalContext<T>,
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        var traversal: TraversalContext<T> = context.deeper

        let children: Dictionary<String, Child>.Values = self.rwLock.withReaderLock {
            self.container.values
        }

        for child in children {
            // result of traversing / descending deeper into the tree
            let descendResult: TraversalResult<T>
            switch child {
            case let .adapter(adapterRef):
                descendResult = adapterRef.traverse(context: context, visit)

            case let .cell(cell):
                descendResult = cell.traverse(context: context, visit)
            }

            // interpreting descent result
            switch descendResult {
            case let .result(value):
                traversal.accumulated.append(value)
                continue

            case let .results(values):
                traversal.accumulated.append(contentsOf: values)
                continue

            case .completed:
                continue

            case .failed:
                return descendResult  // early return, failures abort traversal
            }
        }

        // if we had no children or similar, we simply complete the traversal here; we are a "leaf"
        return traversal.result
    }

    internal func resolve<Message>(context: ResolveContext<Message>) -> ActorRef<Message> {
        guard let selector = context.selectorSegments.first else {
            // no selector, we should not be in this place!
            fatalError("Resolve should have stopped before stepping into children.resolve, this is a bug!")
        }

        let child: Child? = self.rwLock.withReaderLock {
            self.container[selector.value]
        }

        switch child {
        case let .some(.cell(child)):
            return child.resolve(context: context.deeper)

        case let .some(.adapter(child)):
            return child.resolve(context: context.deeper)

        case .none:
            return context.personalDeadLetters
        }
    }

    internal func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef {
        guard let selector = context.selectorSegments.first else {
            // no selector, we should not be in this place!
            fatalError("Resolve should have stopped before stepping into children.resolve, this is a bug!")
        }

        let child: Child? = self.rwLock.withReaderLock {
            self.container[selector.value]
        }

        switch child {
        case let .some(.cell(child)):
            return child.resolveUntyped(context: context.deeper)

        case let .some(.adapter(child)):
            return child.resolveUntyped(context: context.deeper)

        case .none:
            return context.personalDeadLetters.asAddressable
        }
    }
}
