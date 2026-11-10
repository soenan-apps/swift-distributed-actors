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

import Distributed
import Logging
import NIO

/// Implements `DeathWatch` semantics in presence of `Node` failures.
///
/// Depends on a failure detector to actually detect a node failure, however once detected,
/// it handles notifying all _local_ actors which have watched at least one actor the terminating node.
///
/// ### Implementation
/// In order to avoid every actor having to subscribe to cluster events and individually handle the relationship between
/// those
/// and individually watched actors, the watcher handles subscribing for cluster events on behalf of actors which watch
/// other actors on remote nodes, and messages them `SystemMessage.nodeTerminated(node)` upon node termination (down),
/// which are in turn translated by the actors locally to
/// `SystemMessage.terminated(ref:existenceConfirmed:idTerminated:true)`
/// to any actor which watched at least one actor on a node that has been downed.
///
/// Actor which is notified automatically when a remote actor is `context.watch()`-ed.
///
/// Allows manually mocking membership changes to trigger terminated notifications.
internal final class NodeDeathWatcherInstance: NodeDeathWatcher {
    internal struct WatcherAndCallback: Hashable {
        /// Address of the local watcher which had issued this watch
        internal let watcherID: ClusterSystem.ActorID
        internal let callback: @Sendable (Cluster.Node) async -> Void

        internal static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.watcherID == rhs.watcherID
        }

        internal func hash(into hasher: inout Hasher) {
            hasher.combine(self.watcherID)
        }
    }

    private let selfNode: Cluster.Node
    private var membership: Cluster.Membership

    /// Members which have been `removed`
    private var nodeTombstones: Set<Cluster.Node> = []

    /// Mapping between remote node, and actors which have watched some actors on given remote node.
    private var remoteWatchers: [Cluster.Node: Set<AddressableActorRef>] = [:]
    private var remoteWatchCallbacks: [Cluster.Node: Set<WatcherAndCallback>] = [:]

    internal init(selfNode: Cluster.Node) {
        self.selfNode = selfNode
        self.membership = .empty
    }

    internal func onActorWatched(by watcher: AddressableActorRef, remoteNode: Cluster.Node) {
        guard !self.nodeTombstones.contains(remoteNode) else {
            // the system the watcher is attempting to watch has terminated before the watch has been processed,
            // thus we have to immediately reply with a termination system message, as otherwise it would never receive
            // one
            watcher.sendSystemMessage(.nodeTerminated(remoteNode), file: #filePath, line: #line)
            return
        }

        guard watcher.id.isLocal else {
            // a failure detector must never register non-local actors, it would not make much sense,
            // as they should have their own local failure detectors on their own systems.
            // If we reach this it is most likely a bug in the library itself.
            let error: NodeDeathWatcherError = .watcherActorWasNotLocal(
                watcherID: watcher.id,
                localNode: self.selfNode
            )
            return fatalErrorBacktrace(
                "Attempted registering non-local actor with node-death watcher: \(error)",
                file: #file,
                line: #line
            )
        }

        var existingWatchers: Set<AddressableActorRef> = self.remoteWatchers[remoteNode] ?? []
        existingWatchers.insert(watcher)

        self.remoteWatchers[remoteNode] = existingWatchers
    }

    internal func onActorWatched(
        on remoteNode: Cluster.Node,
        by watcher: ClusterSystem.ActorID,
        whenTerminated nodeTerminatedFn: @escaping @Sendable (Cluster.Node) async -> Void
    ) {
        guard !self.nodeTombstones.contains(remoteNode) else {
            // the system the watcher is attempting to watch has terminated before the watch has been processed,
            // thus we have to immediately reply with a termination system message, as otherwise it would never receive
            // one
            Task {
                await nodeTerminatedFn(remoteNode)
            }
            return
        }

        let record: WatcherAndCallback = WatcherAndCallback(watcherID: watcher, callback: nodeTerminatedFn)
        self.remoteWatchCallbacks[remoteNode, default: []].insert(record)
    }

    internal func onRemoveWatcher(
        watcherID: ClusterSystem.ActorID
    ) {
        let removeMe: WatcherAndCallback = WatcherAndCallback(watcherID: watcherID) { _ in () }
        for (node, var callbacks) in self.remoteWatchCallbacks where callbacks.remove(removeMe) != nil {
            self.remoteWatchCallbacks[node] = callbacks
        }
    }

    internal func onMembershipChanged(_ change: Cluster.MembershipChange) {
        guard let appliedChange = self.membership.applyMembershipChange(change) else {
            return  // no change, nothing to act on
        }

        if appliedChange.status >= .down {
            // can be: down, leaving or removal.
            // on any of those we want to ensure we handle the "down"
            self.handleAddressDown(appliedChange)
        }
    }

    internal func handleAddressDown(_ change: Cluster.MembershipChange) {
        let terminatedNode: Cluster.Node = change.node

        // ref
        if let watchers = self.remoteWatchers.removeValue(forKey: terminatedNode) {
            for ref in watchers {
                // we notify each actor that was watching this remote address
                ref.sendSystemMessage(.nodeTerminated(terminatedNode), file: #filePath, line: #line)
            }
        }

        if let watchers = self.remoteWatchCallbacks.removeValue(forKey: terminatedNode) {
            for watcher in watchers {
                Task {
                    await watcher.callback(terminatedNode)
                }
            }
        }

        // we need to keep a tombstone, so we can immediately reply with a terminated,
        // in case another watch was just in progress of being made
        self.nodeTombstones.insert(terminatedNode)
    }
}
