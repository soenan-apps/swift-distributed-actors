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

/// Implements ``LifecycleWatch`` semantics in presence of ``Cluster/Endpoint`` failures.
///
/// Depends on a failure detector (e.g. SWIM) to actually detect a node failure, however once detected,
/// it handles notifying all _local_ actors which have watched at least one actor the terminating node.
///
/// ### Implementation
/// In order to avoid every actor having to subscribe to cluster events and individually handle the relationship between
/// those
/// and individually watched actors, the watcher handles subscribing for cluster events on behalf of actors which watch
/// other actors on remote nodes, and messages them upon a node becoming down.
///
/// Actor which is notified automatically when a remote actor is `context.watch()`-ed.
///
/// Allows manually mocking membership changes to trigger terminated notifications.
internal actor DistributedNodeDeathWatcher {

    internal typealias ActorSystem = ClusterSystem

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

    private let log: Logger

    private let selfNode: Cluster.Node
    private var membership: Cluster.Membership = .empty

    // Members already removed from the cluster.
    private var nodeTombstones: Set<Cluster.Node> = []

    // Local callbacks for actors watched on each remote node.
    private var remoteWatchCallbacks: [Cluster.Node: Set<WatcherAndCallback>] = [:]

    private var eventListenerTask: Task<Void, Error>?

    internal init(actorSystem: ActorSystem) async {
        self.log = actorSystem.log
        self.selfNode = actorSystem.cluster.node
        // initialized

        let events: ClusterEventStream = actorSystem.cluster.events
        self.eventListenerTask = Task {
            for try await event in events {
                switch event {
                case .membershipChange(let change):
                    self.membershipChanged(change)

                case .snapshot(let membership):
                    let diff: MembershipDiff = Cluster.Membership.difference(from: .empty, to: membership)
                    for change in diff.changes {
                        self.membershipChanged(change)
                    }

                case .leadershipChange, .reachabilityChange:
                    break  // ignore those, they don't affect downing

                case .nonExhaustive:
                    self.log.error("Received Cluster.Event [\(event)]. This should not happen, please file an issue.")
                }
            }
        }
    }

    internal func watchActor(
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

    internal func removeWatcher(id: ClusterSystem.ActorID) {
        let removeMe: WatcherAndCallback = WatcherAndCallback(watcherID: id) { _ in () }
        for (node, var callbacks) in self.remoteWatchCallbacks where callbacks.remove(removeMe) != nil {
            self.remoteWatchCallbacks[node] = callbacks
        }
    }

    internal func cleanupTombstone(node: Cluster.Node) {
        _ = self.nodeTombstones.remove(node)
    }

    internal func membershipChanged(_ change: Cluster.MembershipChange) {
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

    internal func cancel() {
        self.eventListenerTask?.cancel()
        self.eventListenerTask = nil
    }
}
