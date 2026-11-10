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

import CoreMetrics
import DistributedActorsConcurrencyHelpers
import Logging
import NIO
import SWIM

extension ClusterShell {
    /// Binds on setup to the configured address (as configured in `system.settings`).
    ///
    /// Once bound proceeds to `ready` state, where it remains to accept or initiate new handshakes.
    internal func bind() -> Behavior<Message> {
        .setup { context in
            try self.startSupportingActors(context)
            let bindNode: Cluster.Node = self.selfNode
            context.log.info("Binding to: [\(bindNode)]")
            let channel: EventLoopFuture<Channel> = self.bootstrapServerSide(
                system: context.system,
                shell: context.myself,
                bindNode: bindNode,
                settings: self.settings,
                serializationPool: self.serializationPool
            )
            return context.awaitResultThrowing(of: channel, timeout: self.settings.bindTimeout) { boundChannel in
                try self.onServerBound(context, channel: boundChannel)
            }
        }
    }

    private func startSupportingActors(_ context: ActorContext<Message>) throws {
        if let discoverySettings = self.settings.discovery {
            let discovery: DiscoveryShell = .init(settings: discoverySettings, cluster: context.myself)
            _ = try context.spawn(DiscoveryShell.naming, discovery.behavior)
        }
        if let election = self.settings.autoLeaderElection.make(context.system.cluster.settings) {
            let shell: Leadership.Shell = Leadership.Shell(election)
            let leadership: ActorRef<Cluster.Event> = try context.spawn(Leadership.Shell.naming, shell.behavior)
            // Leadership failure must trigger shutdown of the cluster shell.
            context.watch(leadership)
        }
    }

    private func onServerBound(_ context: ActorContext<Message>, channel: Channel) throws -> Behavior<Message> {
        context.log.info("Bound to \(channel.localAddress.map(\.description) ?? "<no-local-address>")")
        var state: ClusterShellState = ClusterShellState(
            settings: self.settings,
            channel: channel,
            events: self.clusterEvents,
            gossiperControl: try self.makeMembershipGossiper(context),
            log: context.log
        )
        // Update the snapshot before publishing our initial membership event.
        if let change = state.latestGossip.membership.join(state.selfNode) {
            context.system.cluster.updateMembershipSnapshot(state.membership)
            self.publish(.membershipChange(change))
        }
        return self.ready(state: state)
    }

    private func makeMembershipGossiper(
        _ context: ActorContext<Message>
    ) throws -> GossiperControl<Cluster.MembershipGossip, Cluster.MembershipGossip> {
        try Gossiper.spawn(
            context,
            name: "\(ActorPath.clusterGossipPath.name)",
            settings: .init(
                interval: self.settings.membershipGossipInterval,
                intervalRandomFactor: self.settings.membershipGossipIntervalRandomFactor,
                style: .acknowledged(timeout: self.settings.membershipGossipInterval),
                peerDiscovery: .onClusterMember(atLeast: .joining) { member in
                    let peer: GossipShell<Cluster.MembershipGossip, Cluster.MembershipGossip>.Ref =
                        context.system.resolve(context: .init(
                            id: .clusterGossip(on: member.node), system: context.system
                        ))
                    return peer.asAddressable
                }
            ),
            props: .wellKnown
        ) { logicContext in
            MembershipGossipLogic(
                logicContext,
                notifyOnGossipRef: context.messageAdapter(from: Cluster.MembershipGossip.self) { gossip in
                    Optional.some(Message.gossipFromGossiper(gossip))
                }
            )
        }
    }

    internal func publish(_ event: Cluster.Event) {
        self.publish(event, to: self.clusterEvents)
    }

    internal func publish(_ event: Cluster.Event, to eventStream: ClusterEventStream) {
        Task {
            await eventStream.publish(event)
        }
    }

    /// Called periodically to remove association tombstones after the configured TTL.
    internal func cleanUpAssociationTombstones() -> Behavior<Message> {
        self.associationsLock.withLockVoid {
            for (id, tombstone) in self.associationTombstones where tombstone.removalDeadline.isOverdue() {
                self.associationTombstones.removeValue(forKey: id)
            }
        }
        return .same
    }

    /// Ready and interpreting commands and incoming messages.
    ///
    /// Serves as main "driver" for handshake and association state machines.
    internal func ready(state: ClusterShellState) -> Behavior<Message> {
        Behavior<Message>
            .receive { context, message in
                switch message {
                case .command(let command):
                    return self.receiveShellCommand(context, state: state, command: command)

                case .query(let query):
                    return self.receiveQuery(context, state: state, query: query)

                case .inbound(let inbound):
                    return self.receiveInbound(context, state: state, message: inbound)

                case .requestMembershipChange(let event):
                    return self.receiveChangeMembershipRequest(context, state: state, event: event)

                case .gossipFromGossiper(let gossip):
                    return self.receiveMembershipGossip(context, state, gossip: gossip)
                }
            }
            .receiveSpecificSignal(Signals.Terminated.self) { context, signal in
                context.log.error("Cluster actor \(signal.id) terminated unexpectedly! Will initiate cluster shutdown.")
                try context.system.shutdown()
                // System shutdown will down the node before stopping this shell.
                return .same
            }
    }

    internal func tryConfirmDeadToSWIM(
        _: ActorContext<Message>, _: ClusterShellState, change: Cluster.MembershipChange
    ) {
        if change.status.isAtLeast(.down) {
            self.activeSWIMActor.confirmDead(node: change.member.node)
        }
    }

    internal func tryIntroduceGossipPeer(
        _ context: ActorContext<Message>, _ state: ClusterShellState, change: Cluster.MembershipChange
    ) {
        guard change.status < .down else {
            return
        }
        guard change.member.node != state.selfNode else {
            return
        }

        let gossipPeer: GossipShell<Cluster.MembershipGossip, Cluster.MembershipGossip>.Ref = context.system.resolve(
            context: .init(id: .clusterGossip(on: change.member.node), system: context.system)
        )
        // today it can happen that a node goes down but we dont know yet so we add it again :O
        state.gossiperControl.introduce(peer: gossipPeer)
    }
}
