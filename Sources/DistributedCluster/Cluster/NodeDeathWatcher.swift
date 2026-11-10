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

/// The callbacks defined on a `NodeDeathWatcher` are invoked by an enclosing actor, and thus synchronization is
/// guaranteed
internal protocol NodeDeathWatcher {
    /// Called when the `watcher` watches a remote actor which resides on the `remoteNode`.
    /// A failure detector may have to start monitoring this node using some internal mechanism,
    /// in order to be able to signal the watcher in case the node terminates (e.g. the node crashes).
    func onActorWatched(by watcher: AddressableActorRef, remoteNode: Cluster.Node)

    /// Called when the cluster membership changes.
    ///
    /// A failure detector should signal termination signals if it notices that a previously monitored node has now
    /// left the cluster.
    func onMembershipChanged(_ change: Cluster.MembershipChange)

    func onRemoveWatcher(watcherID: ClusterSystem.ActorID)
}
