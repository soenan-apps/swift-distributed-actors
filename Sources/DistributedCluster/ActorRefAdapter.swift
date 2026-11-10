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

/// Not intended to be used by end users.
///
/// An `ActorRefAdapter` is a special `ActorRef` that is used to expose a different
/// interface than the adapted actor actually has, by applying a converter function
/// to all received messages, before passing them on to the actual actor.
///
/// The adapter can be watched and shares the lifecycle with the adapted actor,
/// meaning that it will terminate when the actor terminates. It will survive
/// restarts after failures.
internal final class ActorRefAdapter<To: Codable>: AbstractAdapter {
    internal let fromType: Any.Type
    private let target: ActorRef<To>
    internal let id: ActorID
    private var watchers: Set<AddressableActorRef>
    // Protected by lock; stopped adapters keep an empty watcher set.
    private var isStopped: Bool = false
    private let lock: ClusterMutex = ClusterMutex()

    internal let deadLetters: ActorRef<DeadLetter>
    private var myselfAddressable: AddressableActorRef {
        ActorRef<Never>(.adapter(self)).asAddressable
    }

    internal var system: ClusterSystem? {
        self.target.actorSystem
    }

    internal init<From>(fromType: From.Type, to ref: ActorRef<To>, id: ActorID) {
        self.fromType = fromType
        self.target = ref
        self.id = id
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
            self.removeWatcher(watchee: self.myselfAddressable, watcher: ref)

        case .carrySignal, .nodeTerminated, .childTerminated, .resume, .start, .stop, .tombstone:
            ()  // ignore all other messages // why?
        }
    }

    @usableFromInline
    internal func trySendUserMessage(_ message: Any, file: String = #filePath, line: UInt = #line) {
        self.target.unsafeUnwrapCell.sendAdaptedMessage(message, file: file, line: line)
    }

    private func addWatcher(watchee: AddressableActorRef, watcher: AddressableActorRef) {
        assert(
            watchee.id == self.id && watcher.id != self.id,
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
            watchee.id == self.id && watcher.id != self.id,
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
            .watch(watchee: watchee, watcher: self.myselfAddressable)
        )
    }

    private func unwatch(_ watchee: AddressableActorRef) {
        watchee.sendSystemMessage(
            .unwatch(watchee: watchee, watcher: self.myselfAddressable)
        )
    }

    private func sendTerminated(_ ref: AddressableActorRef) {
        ref.sendSystemMessage(
            .terminated(ref: self.myselfAddressable, existenceConfirmed: true, idTerminated: false)
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
        let directive: TraversalDirective<T> = visit(context, self.myselfAddressable)

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

    internal func resolve<Message>(context: ResolveContext<Message>) -> ActorRef<Message> {
        guard context.selectorSegments.first == nil,
            self.id.incarnation == context.id.incarnation
        else {
            return context.personalDeadLetters
        }

        return .init(.adapter(self))
    }

    internal func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef {
        guard context.selectorSegments.first == nil, self.id.incarnation == context.id.incarnation else {
            return context.personalDeadLetters.asAddressable
        }

        return self.myselfAddressable
    }
}
