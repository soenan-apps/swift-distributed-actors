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
import Distributed
import DistributedActorsConcurrencyHelpers
import Logging
import NIO

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: LifecycleWatchContainer

/// Implements watching distributed actors for termination.
///
/// Termination of local actors is simply whenever they deinitialize.
/// Remote actors are considered terminated when they deinitialize, same as local actors,
/// or when the node hosting them is declared `.down`.
internal final class LifecycleWatchContainer {

    internal typealias OnTerminatedFn = @Sendable (ClusterSystem.ActorID) async -> Void

    private let _lock: DispatchSemaphore = DispatchSemaphore(value: 1)

    internal let watcherID: ClusterSystem.ActorID
    private let system: ClusterSystem
    private var nodeDeathWatcher: NodeDeathWatcherShell.Ref? {
        self.system.nodeDeathWatcher
    }

    private var watching: [ClusterSystem.ActorID: OnTerminatedFn] = [:]
    private var watchedBy: [ClusterSystem.ActorID: AddressableActorRef] = [:]

    /// Warning: DO NOT RETAIN THE WATCHER.
    internal init(watcherID: ActorID, actorSystem: ClusterSystem) {
        traceLog_DeathWatch("Make LifecycleWatchContainer owned by \(watcherID)", file: #fileID, line: #line)
        self.watcherID = watcherID.withoutLifecycle  // make sure we don't retain the context
        self.system = actorSystem
    }

    internal func clear() {
        self._lock.wait()
        defer {
            _lock.signal()
        }

        traceLog_DeathWatch("Clear LifecycleWatchContainer owned by \(self.watcherID)", file: #fileID, line: #line)
        self.watching = [:]
        self.watchedBy = [:]
        for _ in self.watching.values {  // something off
            self.nodeDeathWatcher?.tell(.removeWatcher(watcherID: self.watcherID))
        }
    }
    /// Performed by the sending side of "watch", therefore the `watcher` should equal `context.myself`
    internal func termination(
        of watcheeID: ActorID,
        @_implicitSelfCapture whenTerminated: @escaping @Sendable (ClusterSystem.ActorID) async -> Void,
        file: String = #filePath,
        line: UInt = #line
    ) {
        self._lock.wait()
        defer {
            self._lock.signal()
        }

        traceLog_DeathWatch("issue watch: \(watcheeID) (from \(self.watcherID))", file: #fileID, line: #line)

        let currentWatcherID: ActorID = self.watcherID

        // watching ourselves is a no-op, since we would never be able to observe the Terminated message anyway:
        guard watcheeID != currentWatcherID else {
            return
        }

        let addressableWatchee: AddressableActorRef = self.system.resolveUntyped(
            context: .init(id: watcheeID, system: self.system)
        )
        let addressableWatcher: AddressableActorRef = self.system.resolveUntyped(
            context: .init(id: currentWatcherID, system: self.system)
        )

        if self.isWatching0(watcheeID) {
            // While we bail out early here, we DO override whichever value was set as the customized termination
            // message.
            // This is to enable being able to keep updating the context associated with a watched actor, e.g. if how
            // we should react to its termination has changed since the last time watch() was invoked.
            self.watching[watcheeID] = whenTerminated
        } else {
            // not yet watching, so let's add it:
            self.watching[watcheeID] = whenTerminated

            addressableWatchee.sendSystemMessage(
                .watch(watchee: addressableWatchee, watcher: addressableWatcher),
                file: file,
                line: line
            )
            self.subscribeNodeTerminatedEvents(watchedID: watcheeID, file: file, line: line)
        }
    }

    /// Reverts the watching of an previously watched actor.
    ///
    /// Unwatching a not-previously-watched actor has no effect.
    ///
    /// ### Semantics for in-flight Terminated signals
    ///
    /// After invoking `unwatch`, even if a `Signals.Terminated` signal was already enqueued at this actors
    /// mailbox; this signal would NOT be delivered to the `onSignal` behavior, since the intent of no longer
    /// watching the terminating actor takes immediate effect.
    ///
    /// #### Concurrency:
    ///  - MUST NOT be invoked concurrently to the actors execution, i.e. from the "outside" of the current actor.
    ///
    /// - Returns: the passed in watchee reference for easy chaining `e.g. return context.unwatch(ref)`
    internal func unwatch<Watchee>(
        watchee: Watchee,
        file: String = #filePath,
        line: UInt = #line
    ) -> Watchee where Watchee: DistributedActor, Watchee.ActorSystem == ClusterSystem {
        self._lock.wait()
        defer {
            _lock.signal()
        }

        traceLog_DeathWatch("issue unwatch: watchee: \(watchee) (from \(self.watcherID)", file: #fileID, line: #line)
        let watcheeID: ActorID = watchee.id
        let currentWatcherID: ActorID = self.watcherID

        // we have to make this nicer, the ID itself must "be" the ref
        let actorSystem: ClusterSystem = watchee.actorSystem
        let addressableWatchee: AddressableActorRef = actorSystem.resolveUntyped(
            context: ResolveContext(id: watcheeID, system: actorSystem)
        )
        let addressableMyself: AddressableActorRef = actorSystem.resolveUntyped(
            context: ResolveContext(id: currentWatcherID, system: actorSystem)
        )

        // we could short circuit "if watchee == myself return" but it's not really worth checking since no-op anyway
        if self.watching.removeValue(forKey: watchee.id) != nil {
            addressableWatchee.sendSystemMessage(
                .unwatch(
                    watchee: addressableWatchee,
                    watcher: addressableMyself
                ),
                file: file,
                line: line
            )
        }

        return watchee
    }

    /// - Returns `true` if the passed in actor ref is being watched
    @usableFromInline
    internal func isWatching(_ identity: ClusterSystem.ActorID) -> Bool {
        self._lock.wait()
        defer {
            _lock.signal()
        }

        return self.isWatching0(identity)
    }

    @usableFromInline
    internal func isWatching0(_ identity: ClusterSystem.ActorID) -> Bool {
        self.watching[identity] != nil
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: react to watch or unwatch signals

    /// Registers an actor that must be notified when this actor terminates.
    internal func becomeWatchedBy(watcher: AddressableActorRef) {
        self._lock.wait()
        defer {
            _lock.signal()
        }

        guard watcher.id != self.watcherID else {
            traceLog_DeathWatch(
                "Attempted to watch 'myself' [\(self.watcherID)], which is a no-op, "
                    + "since such watch's terminated can never be observed. "
                    + "Likely a programming error where the wrong actor ref was passed to watch(), "
                    + "please check your code.",
                file: #fileID,
                line: #line
            )
            return
        }

        traceLog_DeathWatch(
            "Become watched by: \(watcher.id)     inside: \(self.watcherID)",
            file: #fileID,
            line: #line
        )
        self.watchedBy[watcher.id] = watcher
    }

    internal func removeWatchedBy(watcher: AddressableActorRef) {
        self._lock.wait()
        defer {
            _lock.signal()
        }

        traceLog_DeathWatch(
            "Remove watched by: \(watcher.id)     inside: \(self.watcherID)",
            file: #fileID,
            line: #line
        )
        self.watchedBy.removeValue(forKey: watcher.id)
    }

    /// Performs cleanup of references to the dead actor.
    internal func receiveTerminated(_ terminated: Signals.Terminated) {
        self.receiveTerminated0(terminated.id)
    }

    internal func receiveTerminated(_ terminatedID: ClusterSystem.ActorID) {
        self._lock.wait()
        defer {
            _lock.signal()
        }

        self.receiveTerminated0(terminatedID)
    }

    private func receiveTerminated0(_ terminatedID: ClusterSystem.ActorID) {
        // we remove the actor from both sets;
        // 1) we don't need to watch it anymore, since it has just terminated,
        let removedOnTerminationFn: OnTerminatedFn? = self.watching.removeValue(forKey: terminatedID)
        // 2) we don't need to refer to it, since sending it .terminated notifications would be pointless.
        _ = self.watchedBy.removeValue(forKey: terminatedID)

        guard let onTermination = removedOnTerminationFn else {
            // if we had no stored/removed termination message, it means this actor was NOT watched actually.
            // Meaning: don't deliver Signal/message to user actor.
            return
        }

        Task {
            // we could surface the additional information (node terminated, existence confirmed) too
            await onTermination(terminatedID)
        }
    }

    /// Performs cleanup of any actor references that were located on the now terminated node.
    ///
    /// Causes `Terminated` signals to be triggered for any such watched remote actor.
    ///
    /// Does NOT immediately handle these `Terminated` signals, they are treated as any other normal signal would,
    /// such that the user can have a chance to handle and react to them.
    private func receiveNodeTerminated(_ terminatedNode: Cluster.Node) {
        self._lock.wait()
        defer {
            _lock.signal()
        }

        let terminatedIDs: [ActorID] = self.watching.keys.filter { $0.node == terminatedNode }
        for terminatedID in terminatedIDs {
            self.receiveTerminated0(terminatedID)
            self.watching.removeValue(forKey: terminatedID)
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Myself termination

    internal func notifyWatchersWeDied() {
        traceLog_DeathWatch(
            "[\(self.watcherID)] notifyWatchers that we are terminating. Watchers: \(self.watchedBy)...",
            file: #fileID,
            line: #line
        )

        for (recipientID, watcherRef) in self.watchedBy {
            traceLog_DeathWatch(
                "[\(recipientID)] Notify  \(recipientID) (\(watcherRef)) that we died",
                file: #fileID,
                line: #line
            )
            let fakeRef: ActorRef<Done> = ActorRef<Done>(
                .deadLetters(.init(.init(label: "x"), id: self.watcherID, system: nil))
            )
            watcherRef.sendSystemMessage(
                .terminated(ref: fakeRef.asAddressable, existenceConfirmed: true),
                file: #filePath,
                line: #line
            )
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Cluster.Node termination

    private func subscribeNodeTerminatedEvents(
        watchedID: ActorID,
        file: String = #filePath,
        line: UInt = #line
    ) {
        self.nodeDeathWatcher?.tell(  // different actor
            .remoteDistributedActorWatched(
                remoteNode: watchedID.node,
                watcherID: self.watcherID
            ) { [weak self, weak system] node in
                guard let self else {
                    return
                }

                Task {
                    self.receiveNodeTerminated(node)
                }

                guard let system = system else {
                    return
                }

                let myselfRef: AddressableActorRef = system.resolveUntyped(
                    context: .init(id: self.watcherID, system: system)
                )
                myselfRef.sendSystemMessage(.nodeTerminated(node), file: file, line: line)
            }
        )
    }

    deinit {
        self.clear()
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: perform watch/unwatch

// ensure all those calls are made on the owning actor's context.
