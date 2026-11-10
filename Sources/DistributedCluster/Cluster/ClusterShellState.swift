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

import DistributedActorsConcurrencyHelpers
import Logging
import NIO

internal struct ClusterShellState: ReadOnlyClusterState {
    internal typealias Messages = ClusterShell.Message

    internal var log: Logger
    internal let settings: ClusterSystemSettings

    internal let events: ClusterEventStream

    internal let channel: Channel

    internal let selfNode: Cluster.Node
    internal var selfMember: Cluster.Member {
        if let member = self.membership.member(self.selfNode) {
            return member
        }
        fatalError(
            """
                ClusterShellState.selfMember was nil! This should be impossible by construction, \
                because a node ALWAYS knows about itself.
                Please report a bug on the distributed-actors issue tracker. Details:
                Membership: \(self.membership)
                Settings: \(self.settings)
                """
        )
    }

    internal let eventLoopGroup: EventLoopGroup

    internal var handshakeBackoff: BackoffStrategy {
        self.settings.handshakeReconnectBackoff
    }

    internal let allocator: ByteBufferAllocator

    internal var handshakesByEndpoint: [Cluster.Endpoint: HandshakeStateMachine.State] = [:]

    internal let gossiperControl: GossiperControl<Cluster.MembershipGossip, Cluster.MembershipGossip>

    /// Updating the `latestGossip` causes the gossiper to be informed about it, such that the next time it does a
    /// gossip round
    /// it uses the latest gossip available.
    internal var latestGossipStorage: Cluster.MembershipGossip

    /// Any change to the gossip data, is propagated to the gossiper immediately.
    internal var latestGossip: Cluster.MembershipGossip {
        get {
            self.latestGossipStorage
        }
        set {
            if self.latestGossipStorage.membership == newValue.membership {
                self.latestGossipStorage = newValue
            } else {
                let next: Cluster.MembershipGossip
                if self.latestGossipStorage.version == newValue.version {
                    next = newValue.incrementingOwnerVersion()
                } else {
                    next = newValue
                }

                self.latestGossipStorage = next
            }
            self.gossiperControl.update(payload: self.latestGossipStorage)
        }
    }

    internal var membership: Cluster.Membership {
        get {
            self.latestGossip.membership
        }
        set {
            self.latestGossip.membership = newValue
        }
    }

    internal init(
        settings: ClusterSystemSettings,
        channel: Channel,
        events: ClusterEventStream,
        gossiperControl: GossiperControl<Cluster.MembershipGossip, Cluster.MembershipGossip>,
        log: Logger
    ) {
        self.log = log
        self.settings = settings
        self.allocator = settings.allocator
        self.eventLoopGroup = settings.eventLoopGroup ?? settings.makeDefaultEventLoopGroup()

        self.selfNode = settings.bindNode
        self.latestGossipStorage = Cluster.MembershipGossip(ownerNode: settings.bindNode)

        self.events = events
        self.gossiperControl = gossiperControl
        self.channel = channel
    }

    internal func handshakes() -> [HandshakeStateMachine.State] {
        Array(self.handshakesByEndpoint.values)
    }
}
