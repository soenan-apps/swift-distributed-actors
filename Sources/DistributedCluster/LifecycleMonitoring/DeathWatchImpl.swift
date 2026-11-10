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
import Logging
import NIO

// Implementation notes:
// Care was taken to keep this implementation separate from the ActorCell however not require more storage space.
/// DeathWatch implements the user facing `watch` and `unwatch` functions.
/// It allows actors to watch other actors for termination, and also takes into account clustering lifecycle
/// information,
/// e.g. if a node is declared `.down` all actors on given node are assumed to have terminated, causing the appropriate
/// `Terminated` signals.
///
/// An `ActorShell` owns a death watch instance and is responsible of managing all calls to it.
@usableFromInline
internal struct DeathWatchImpl<Message: Codable> {

    private enum OnTerminationMessage {
        case defaultTerminatedSignal
        case custom(Message)

        init(customize custom: Message?) {
            if let custom = custom {
                self = .custom(custom)
            } else {
                self = .defaultTerminatedSignal
            }
        }
    }

    /// instructs the ActorShell to either deliver a Terminated signal or the customized message (from watch(:with:))
    internal enum TerminatedMessageDirective {
        case wasNotWatched
        case signal
        case customMessage(Message)
    }

    private var watching: [AddressableActorRef: OnTerminationMessage] = [:]
    private var watchedBy: Set<AddressableActorRef> = []

    private var nodeDeathWatcher: NodeDeathWatcherShell.Ref

    internal init(nodeDeathWatcher: NodeDeathWatcherShell.Ref) {
        self.nodeDeathWatcher = nodeDeathWatcher
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: perform watch/unwatch

    /// Performed by the sending side of "watch", therefore the `watcher` should equal `context.myself`
    internal mutating func watch<Watchee>(
        watchee: Watchee,
        with terminationMessage: Message?,
        myself watcher: ActorShell<Message>,
        file: String,
        line: UInt
    ) where Watchee: DeathWatchable {
        traceLog_DeathWatch("issue watch: \(watchee) (from \(watcher) (myself))", file: #fileID, line: #line)
        let addressableWatchee: AddressableActorRef = watchee.asAddressable

        // watching ourselves is a no-op, since we would never be able to observe the Terminated message anyway:
        guard addressableWatchee.id != watcher.id else {
            return
        }

        if self.isWatching(addressableWatchee.id) {
            // While we bail out early here, we DO override whichever value was set as the customized termination
            // message.
            // This is to enable being able to keep updating the context associated with a watched actor, e.g. if how
            // we should react to its termination has changed since the last time watch() was invoked.
            self.watching[addressableWatchee] = OnTerminationMessage(customize: terminationMessage)

            return
        }
        // not yet watching, so let's add it:
        self.watching[addressableWatchee] = OnTerminationMessage(customize: terminationMessage)

        if !watcher.children.contains(identifiedBy: watchee.asAddressable.id) {
            // We ONLY send the watch message if it is NOT our own child;
            //
            // Because a child ALWAYS sends a .childTerminated to its parent on termination, so there is no need to
            // watch it again,
            // other than _us_ remembering that we issued such watch. A child can also never be remote, so the node
            // deathwatcher does not matter either.
            //
            // A childTerminated is transformed into `Signals.ChildTerminated` which subclasses `Signals.Terminated`,
            // so this way we achieve exactly one termination notification already.
            addressableWatchee.sendSystemMessage(
                .watch(watchee: addressableWatchee, watcher: watcher.asAddressable),
                file: file,
                line: line
            )
        }

        self.subscribeNodeTerminatedEvents(
            myself: watcher.myself,
            watchedID: addressableWatchee.id,
            file: file,
            line: line
        )
    }

    /// Performed by the sending side of "unwatch", the watchee should equal "context.myself"
    internal mutating func unwatch<Watchee>(
        watchee: Watchee,
        myself watcher: ActorRef<Message>,
        file: String = #filePath,
        line: UInt = #line
    ) where Watchee: DeathWatchable {
        traceLog_DeathWatch("issue unwatch: watchee: \(watchee) (from \(watcher) myself)", file: #fileID, line: #line)
        let addressableWatchee: AddressableActorRef = watchee.asAddressable
        // we could short circuit "if watchee == myself return" but it's not really worth checking since no-op anyway
        if self.watching.removeValue(forKey: addressableWatchee) != nil {
            addressableWatchee.sendSystemMessage(
                .unwatch(watchee: addressableWatchee, watcher: AddressableActorRef(watcher)),
                file: file,
                line: line
            )
        }
    }

    /// - Returns `true` if the passed in actor ref is being watched
    @usableFromInline
    internal func isWatching(_ id: ActorID) -> Bool {
        let mockRefForEquality: AddressableActorRef = ActorRef<Never>(
            .deadLetters(.init(.init(label: "x"), id: id, system: nil))
        ).asAddressable
        return self.watching[mockRefForEquality] != nil
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: react to watch or unwatch signals

    internal mutating func becomeWatchedBy(
        watcher: AddressableActorRef,
        myself: ActorRef<Message>,
        parent: AddressableActorRef
    ) {
        guard watcher.id != myself.id else {
            traceLog_DeathWatch(
                "Attempted to watch 'myself' [\(myself)], which is a no-op, "
                    + "since such watch's terminated can never be observed. "
                    + "Likely a programming error where the wrong actor ref was passed to watch(), "
                    + "please check your code.",
                file: #fileID,
                line: #line
            )
            return
        }

        guard watcher != parent else {
            // This is fairly defensive, as the parent should already know to never send such message, but let's better
            // be safe than sorry.
            //
            // no need to become watched by parent, we always notify our parent with `childTerminated` anyway already
            // so if we added it also to `watchedBy` we would potentially send terminated twice: terminated and
            // childTerminated,
            // which is NOT good -- we only should notify it once, specifically with the childTerminated signal handled
            // by the ActorShell itself.
            return
        }

        traceLog_DeathWatch("Become watched by: \(watcher.id)     inside: \(myself)", file: #fileID, line: #line)
        self.watchedBy.insert(watcher)
    }

    @usableFromInline
    internal mutating func removeWatchedBy(watcher: AddressableActorRef, myself: ActorRef<Message>) {
        traceLog_DeathWatch("Remove watched by: \(watcher.id)     inside: \(myself)", file: #fileID, line: #line)
        self.watchedBy.remove(watcher)
    }

    /// Performs cleanup of references to the dead actor.
    ///
    /// Returns: `true` if the termination was concerning a currently watched actor, false otherwise.
    internal mutating func receiveTerminated(_ terminated: Signals.Terminated) -> TerminatedMessageDirective {
        // refs are compared ONLY by address, thus we can make such mock reference, and it will be properly remove the
        // right "real" refs from the collections below
        let mockRefForEquality: AddressableActorRef = ActorRef<Never>(
            .deadLetters(.init(.init(label: "x"), id: terminated.id, system: nil))
        ).asAddressable

        // we remove the actor from both sets;
        // 1) we don't need to watch it anymore, since it has just terminated,
        let removedOnTerminationMessage: OnTerminationMessage? = self.watching.removeValue(forKey: mockRefForEquality)
        // 2) we don't need to refer to it, since sending it .terminated notifications would be pointless.
        _ = self.watchedBy.remove(mockRefForEquality)

        guard let onTerminationMessage = removedOnTerminationMessage else {
            // if we had no stored/removed termination message, it means this actor was NOT watched actually.
            // Meaning: don't deliver Signal/message to user actor.
            return .wasNotWatched
        }

        switch onTerminationMessage {
        case .defaultTerminatedSignal:
            return .signal

        case .custom(let message):
            return .customMessage(message)
        }
    }

    /// Performs cleanup of any actor references that were located on the now terminated node.
    ///
    /// Causes `Terminated` signals to be triggered for any such watched remote actor.
    ///
    /// Does NOT immediately handle these `Terminated` signals, they are treated as any other normal signal would,
    /// such that the user can have a chance to handle and react to them.
    @usableFromInline
    internal mutating func receiveNodeTerminated(_ terminatedNode: Cluster.Node, myself: ReceivesSystemMessages) {
        for watched: AddressableActorRef in self.watching.keys where watched.id.node == terminatedNode {
            // we KNOW an actor existed if it is local and not resolved as /dead; otherwise it may have existed
            // for a remote ref we don't know for sure if it existed
            let existenceConfirmed: Bool = watched.refType.isLocal && !watched.id.path.starts(with: .dead)
            myself.sendSystemMessage(
                .terminated(ref: watched, existenceConfirmed: existenceConfirmed, idTerminated: true),
                file: #filePath,
                line: #line
            )
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------

    // MARK: Myself termination

    internal func notifyWatchersWeDied(myself: ActorRef<Message>) {
        traceLog_DeathWatch(
            "[\(myself)] notifyWatchers that we are terminating. Watchers: \(self.watchedBy)...",
            file: #fileID,
            line: #line
        )

        for watcher in self.watchedBy {
            traceLog_DeathWatch("[\(myself)] Notify \(watcher) that we died", file: #fileID, line: #line)
            watcher.sendSystemMessage(
                .terminated(ref: AddressableActorRef(myself), existenceConfirmed: true),
                file: #filePath,
                line: #line
            )
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Cluster.Node termination

    private func subscribeNodeTerminatedEvents(
        myself: ActorRef<Message>,
        watchedID: ActorID,
        file: String = #filePath,
        line: UInt = #line
    ) {
        guard watchedID.isRemote else {
            return
        }
        self.nodeDeathWatcher.tell(
            .remoteActorWatched(watcher: AddressableActorRef(myself), remoteNode: watchedID.node),
            file: file,
            line: line
        )
    }
}
