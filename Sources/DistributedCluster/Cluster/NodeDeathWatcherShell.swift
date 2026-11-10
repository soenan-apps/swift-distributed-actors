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

internal enum NodeDeathWatcherShell {
    internal typealias Ref = ActorRef<Message>

    /// Messages consumed by the node watcher shell.
    internal enum Message: NotActuallyCodableMessage {
        case membershipChange(Cluster.MembershipChange)
        case membershipSnapshot(Cluster.Membership)
        case remoteActorWatched(watcher: AddressableActorRef, remoteNode: Cluster.Node)
        case remoteDistributedActorWatched(
            remoteNode: Cluster.Node,
            watcherID: ClusterSystem.ActorID,
            nodeTerminated: @Sendable (Cluster.Node) async -> Void
        )
        case removeWatcher(watcherID: ClusterSystem.ActorID)
    }

    internal static var naming: ActorNaming {
        "nodeDeathWatcher"
    }

    internal static func behavior(clusterEvents _: ClusterEventStream) -> Behavior<Message> {
        .setup { context in
            let instance: NodeDeathWatcherInstance = .init(selfNode: context.system.settings.bindNode)

            let onClusterEventRef: ActorRef<Cluster.Event> = context.subReceive(Cluster.Event.self) { event in
                Self.applyClusterEvent(event, to: instance, log: context.log)
            }
            context.system.cluster.events.subscribe(onClusterEventRef)

            return Self.behavior(instance)
        }
    }

    internal static func behavior(_ instance: NodeDeathWatcherInstance) -> Behavior<Message> {
        .receive { context, message in
            context.log.debug("Received: \(message)")
            switch message {
            case let .remoteActorWatched(watcher, remoteNode):
                instance.onActorWatched(by: watcher, remoteNode: remoteNode)

            case let .remoteDistributedActorWatched(remoteNode, watcherID, nodeTerminatedFn):
                instance.onActorWatched(on: remoteNode, by: watcherID, whenTerminated: nodeTerminatedFn)

            case .removeWatcher(let watcherID):
                instance.onRemoveWatcher(watcherID: watcherID)

            case .membershipSnapshot(let membership):
                let diff: MembershipDiff = Cluster.Membership.difference(from: .empty, to: membership)

                for change in diff.changes {
                    instance.onMembershipChanged(change)
                }

            case .membershipChange(let change):
                instance.onMembershipChanged(change)
            }
            return .same
        }
    }

    internal static func applyClusterEvent(
        _ event: Cluster.Event, to instance: NodeDeathWatcherInstance, log: Logger
    ) {
        switch event {
        case .snapshot(let membership):
            log.trace("Membership snapshot: \(membership)")
            let diff: MembershipDiff = Cluster.Membership.difference(from: .empty, to: membership)
            for change in diff.changes {
                instance.onMembershipChanged(change)
            }

        case .membershipChange(let change) where change.isAtLeast(.down):
            log.trace(
                "Node down: \(change)!",
                metadata: [
                    "node": .string("\(reflecting: change.node)")
                ]
            )
            instance.handleAddressDown(change)

        case .membershipChange(let change):
            log.trace(
                "Node change: \(change)!",
                metadata: [
                    "node": .string("\(reflecting: change.node)")
                ]
            )
            instance.onMembershipChanged(change)

        default:
            ()  // ignore other changes, we only need to react on nodes becoming DOWN
        }
    }
}
