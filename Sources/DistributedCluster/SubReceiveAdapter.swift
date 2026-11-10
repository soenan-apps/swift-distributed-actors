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

internal final class SubReceiveAdapter<Message: Codable, OwnerMessage: Codable>: AbstractAdapter {
    internal let fromType: Any.Type

    private let target: ActorRef<OwnerMessage>
    private let identifier: AnySubReceiveId
    private let adapterAddress: ActorID
    private var watchers: Set<AddressableActorRef>
    // Protected by lock; stopped adapters keep an empty watcher set.
    private var isStopped: Bool = false
    private let lock: ClusterMutex = ClusterMutex()

    internal var id: ActorID {
        self.adapterAddress
    }

    internal let deadLetters: ActorRef<DeadLetter>
    private var myself: ActorRef<Message> {
        ActorRef(.adapter(self))
    }

    internal var system: ClusterSystem? {
        self.target.actorSystem
    }

    internal init(_: Message.Type, owner ref: ActorRef<OwnerMessage>, id: ActorID, identifier: AnySubReceiveId) {
        self.fromType = Message.self
        self.target = ref
        self.adapterAddress = id
        self.identifier = identifier
        self.watchers = []

        // since we are an adapter, we must be attached to some "real" actor ref (be it local, remote or dead),
        // thus we should be able to reach a real dead letters instance by going through the target ref.
        self.deadLetters = self.target.deadLettersRef
    }
    internal func sendSystemMessage(_ message: SystemMessages, file _: String = #filePath, line _: UInt = #line) {
        switch message {
        case let .watch(watchee, watcher):
            self.addWatcher(watchee: watchee, watcher: watcher)

        case let .unwatch(watchee, watcher):
            self.removeWatcher(watchee: watchee, watcher: watcher)

        case let .terminated(ref, _, _):
            self.removeWatcher(watchee: self.myself.asAddressable, watcher: ref)

        case .nodeTerminated, .childTerminated, .carrySignal, .resume, .start, .stop, .tombstone:
            ()  // ignore all other messages // why?
        }
    }

    @usableFromInline
    internal func sendUserMessage(_ message: Message, file _: String = #filePath, line _: UInt = #line) {
        self.target.unsafeUnwrapCell.sendSubMessage(
            message,
            identifier: self.identifier,
            subReceiveAddress: self.adapterAddress
        )
    }

    @usableFromInline
    internal func trySendUserMessage(_ message: Any, file: String = #filePath, line: UInt = #line) {
        if let typedMessage = message as? Message {
            self.sendUserMessage(typedMessage, file: file, line: line)
        } else {
            if let directMessage = message as? OwnerMessage {
                fatalError(
                    """
                    trySendUserMessage on subReceive \(self.myself) was attempted with \
                    `To = \(OwnerMessage.self)` message [\(directMessage)], which is the \
                    original adapted-to message type. This should never happen, as on \
                    compile-level the message type should have been enforced to be `From \
                    = \(Message.self)`.
                    """
                )
            } else {
                traceLog_Mailbox(
                    self.id.path,
                    """
                    trySendUserMessage: [\(message)] failed because of invalid message \
                    type, to: \(self)
                    """
                )
                return  // "drop" the message
            }
        }
    }

    private func addWatcher(watchee: AddressableActorRef, watcher: AddressableActorRef) {
        assert(
            watchee.id == self.adapterAddress && watcher.id != self.adapterAddress,
            "Illegal watch received. Watchee: [\(watchee)], watcher: [\(watcher)]"
        )

        self.lock.synchronized {
            guard !self.isStopped else {
                self.sendTerminated(watcher)
                return
            }

            guard !self.watchers.contains(watcher) else {
                return
            }

            self.watchers.insert(watcher)
            self.watch(watcher)
        }
    }

    private func removeWatcher(watchee: AddressableActorRef, watcher: AddressableActorRef) {
        assert(
            watchee.id == self.adapterAddress && watcher.id != self.adapterAddress,
            "Illegal unwatch received. Watchee: [\(watchee)], watcher: [\(watcher)]"
        )

        self.lock.synchronized {
            guard !self.isStopped else {
                return
            }

            self.watchers.remove(watcher)
        }
    }

    private func watch(_ watchee: AddressableActorRef) {
        watchee.sendSystemMessage(
            .watch(watchee: watchee, watcher: self.myself.asAddressable)
        )
    }

    private func unwatch(_ watchee: AddressableActorRef) {
        watchee.sendSystemMessage(
            .unwatch(watchee: watchee, watcher: self.myself.asAddressable)
        )
    }

    private func sendTerminated(_ ref: AddressableActorRef) {
        ref.sendSystemMessage(
            .terminated(ref: self.myself.asAddressable, existenceConfirmed: true, idTerminated: false)
        )
    }

    internal func stop() {
        var localWatchers: Set<AddressableActorRef> = []
        self.lock.synchronized {
            guard !self.isStopped else {
                return
            }

            localWatchers = self.watchers
            self.watchers = []
            self.isStopped = true
        }

        for watcher in localWatchers {
            self.unwatch(watcher)
            self.sendTerminated(watcher)
        }
    }
    internal func traverse<T>(
        context: TraversalContext<T>,
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        var traversal: TraversalContext<T> = context.deeper
        let directive: TraversalDirective<T> = visit(context, self.myself.asAddressable)

        switch directive {
        case .continue:
            ()

        case let .accumulateSingle(value):
            traversal.accumulated.append(value)

        case let .accumulateMany(values):
            traversal.accumulated.append(contentsOf: values)

        case let .abort(err):
            return .failed(err)
        }

        return traversal.result
    }

    internal func resolve<M>(context: ResolveContext<M>) -> ActorRef<M> {
        guard context.selectorSegments.first == nil,
            self.id.incarnation == context.id.incarnation
        else {
            return context.personalDeadLetters
        }

        switch self.myself {
        case let resolvedActor as ActorRef<M>:
            return resolvedActor

        default:
            return context.personalDeadLetters
        }
    }

    internal func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef {
        guard context.selectorSegments.first == nil, self.id.incarnation == context.id.incarnation else {
            return context.personalDeadLetters.asAddressable
        }

        return self.myself.asAddressable
    }
}
