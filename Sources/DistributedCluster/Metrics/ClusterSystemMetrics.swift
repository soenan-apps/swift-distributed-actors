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

// Modified by Soenan to distinguish up members from joining members.
import DistributedActorsConcurrencyHelpers
import Metrics
import SWIM

/// Carries references to all metrics objects for simple and structured usage throughout the actor system.
///
/// Implementation note: Metrics should be updated by using some dedicated meaningfully named method, e.g.
/// `recordActorStart()`,
/// rather than directly updating counters from library code, such that which counter is updated and how is encapsulated
/// in this file,
/// and is possible to refer to when wanting to understand metrics.
///
/// ### Naming
/// Metric labels use backend-specific segments separated by `.`, `/`, or `_`.
///
/// - SeeAlso: [SwiftMetrics](https://github.com/apple/swift-metrics) for compatible backend implementations.
@usableFromInline
internal final class ClusterSystemMetrics {
    internal let settings: MetricsSettings

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Actor Metrics (global)

    // Note: To calculate number of current alive actors, calculate: `actors.lifecycle { event=start } -
    // actors.lifecycle { event=stop }`

    /// actors.lifecycle { root=/user, event=start }
    /// actors.lifecycle { root=/user, event=stop }
    internal let actorsLifecycleUser: MetricsPNCounter
    /// actors.lifecycle { root=/system, event=start }
    /// actors.lifecycle { root=/system, event=stop }
    internal let actorsLifecycleSystem: MetricsPNCounter

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Cluster Metrics

    /// cluster.members
    internal let clusterMembers: Gauge
    /// cluster.members
    internal let clusterMembersJoining: Gauge
    internal let clusterMembersUp: Gauge
    internal let clusterMembersLeaving: Gauge
    internal let clusterMembersDown: Gauge
    internal let clusterMembersRemoved: Gauge

    internal let clusterUnreachableMembers: Gauge

    internal let clusterAssociationTombstones: Gauge

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: SWIM (Cluster) Metrics

    // `SWIM.Metrics` are emitted by the `SWIM.Instance` automatically
    // See also the metrics emitted in `ActorSWIMShell`

    internal let systemMsgRedeliveryBuffer: Gauge

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Receptionist
    /// Total number of actors registered with receptionist
    internal let receptionistKeys: Gauge
    /// Total number of actors registered with receptionist
    internal let receptionistRegistrations: MetricsPNCounter

    /// Size of the op-log in the `OpLogClusterReceptionist`
    internal let receptionistOplogSize: Gauge

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Serialization Metrics

    internal let serializationSystemOutboundMsgSize: Recorder
    internal let serializationSystemInboundMsgSize: Recorder

    internal let serializationUserOutboundMsgSize: Recorder
    internal let serializationUserInboundMsgSize: Recorder

    internal init(_ settings: MetricsSettings) {
        self.settings = settings

        // ==== Actors ----------------------------------------------
        let dimStart: (String, String) = ("event", "start")
        let dimStop: (String, String) = ("event", "stop")
        let rootUser: (String, String) = ("root", "/user")
        let rootSystem: (String, String) = ("root", "/system")

        let actorsLifecycleLabel: String = settings.makeLabel("actors", "lifecycle")
        self.actorsLifecycleUser = .init(
            label: actorsLifecycleLabel,
            positive: [rootUser, dimStart],
            negative: [rootUser, dimStop]
        )
        self.actorsLifecycleSystem = .init(
            label: actorsLifecycleLabel,
            positive: [rootSystem, dimStart],
            negative: [rootSystem, dimStop]
        )

        // ==== Serialization -----------------------------------------------
        self.systemMsgRedeliveryBuffer = .init(label: settings.makeLabel("system", "redelivery_buffer", "count"))

        // ==== Serialization -----------------------------------------------
        let serializationLabel: String = settings.makeLabel("serialization")
        let dimInbound: (String, String) = ("direction", "in")
        let dimOutbound: (String, String) = ("direction", "out")
        self.serializationSystemOutboundMsgSize = .init(
            label: serializationLabel,
            dimensions: [rootSystem, dimOutbound]
        )
        self.serializationSystemInboundMsgSize = .init(label: serializationLabel, dimensions: [rootSystem, dimInbound])
        self.serializationUserOutboundMsgSize = .init(label: serializationLabel, dimensions: [rootUser, dimOutbound])
        self.serializationUserInboundMsgSize = .init(label: serializationLabel, dimensions: [rootUser, dimInbound])
        // record message types by type

        // ==== Receptionist ----------------------------------------
        self.receptionistKeys = .init(label: settings.makeLabel("receptionist", "keys"))
        self.receptionistRegistrations = .init(
            label: settings.makeLabel("receptionist", "actors"),
            positive: [("type", "registered")],
            negative: [("type", "removed")]
        )
        self.receptionistOplogSize = .init(label: settings.makeLabel("receptionist", "oplog", "size"))

        // ==== Cluster ---------------------------------------------
        let clusterMembersLabel: String = settings.makeLabel("cluster", "members")
        self.clusterMembers = .init(label: clusterMembersLabel)
        self.clusterMembersJoining = Self.makeMembershipGauge(label: clusterMembersLabel, status: .joining)
        self.clusterMembersUp = Self.makeMembershipGauge(label: clusterMembersLabel, status: .operational)
        self.clusterMembersLeaving = Self.makeMembershipGauge(label: clusterMembersLabel, status: .leaving)
        self.clusterMembersDown = Self.makeMembershipGauge(label: clusterMembersLabel, status: .down)
        // this is equal to number of stored tombstones kind of
        self.clusterMembersRemoved = Self.makeMembershipGauge(label: clusterMembersLabel, status: .removed)
        self.clusterUnreachableMembers = .init(
            label: clusterMembersLabel,
            dimensions: [("reachability", Cluster.MemberReachability.unreachable.rawValue)]
        )

        let clusterAssociations: String = settings.makeLabel("cluster", "associations")
        self.clusterAssociationTombstones = .init(label: clusterAssociations)
    }

    private static func makeMembershipGauge(label: String, status: Cluster.MemberStatus) -> Gauge {
        Gauge(label: label, dimensions: [("status", status.rawValue)])
    }

    internal func recordActorStart<Anything>(_ shell: ActorShell<Anything>) {
        // use specific dimensions if shell has it configured or groups etc
        // generalize this such that we can do props -> dimensions -> done, and not special case the system ones
        guard let root = shell.path.segments.first else {
            return  // do nothing
        }
        switch root {
        case ActorPathSegment.systemRoot:
            self.actorsLifecycleSystem.increment()

        case ActorPathSegment.userRoot:
            self.actorsLifecycleUser.increment()

        default:
            fatalError("TODO other actor path roots not supported; Was: \(shell)")
        }
    }

    internal func recordActorStop<Anything>(_ shell: ActorShell<Anything>) {
        // use specific dimensions if shell has it configured or groups etc
        // generalize this such that we can do props -> dimensions -> done, and not special case the system ones
        guard let root = shell.path.segments.first else {
            return  // do nothing
        }
        switch root {
        case ActorPathSegment.systemRoot:
            self.actorsLifecycleSystem.decrement()

        case ActorPathSegment.userRoot:
            self.actorsLifecycleUser.decrement()

        default:
            fatalError("TODO other actor path roots not supported; Was: \(shell)")
        }
    }

    internal func recordMembership(_ membership: Cluster.Membership) {
        let members: [Cluster.Member] = membership.members(atLeast: .joining)

        var joining: Int = 0
        var operationalCount: Int = 0
        var leaving: Int = 0
        var down: Int = 0
        var removed: Int = 0
        var unreachable: Int = 0
        for member in members {
            switch member.status {
            case .joining:
                joining += 1

            case .operational:
                operationalCount += 1

            case .down:
                down += 1

            case .leaving:
                leaving += 1

            case .removed:
                removed += 1

            case .nonExhaustive:
                ()
            }

            switch member.reachability {
            case .unreachable:
                unreachable += 1

            default:
                ()  // skip
            }

            self.clusterMembers.record(operationalCount)
            self.clusterMembersJoining.record(joining)
            self.clusterMembersUp.record(operationalCount)
            self.clusterMembersLeaving.record(leaving)
            self.clusterMembersDown.record(down)
            self.clusterMembersRemoved.record(removed)
            self.clusterUnreachableMembers.record(unreachable)
        }
    }

    internal func recordTombstones(count: Int) {
        self.clusterAssociationTombstones.record(count)
    }

    @usableFromInline
    internal func recordSerializationMessageOutbound(_ path: ActorPath, _ bytes: Int) {
        if path.starts(with: .userRoot) {
            self.serializationUserOutboundMsgSize.record(bytes)
        } else if path.starts(with: .systemRoot) {
            self.serializationSystemOutboundMsgSize.record(bytes)
        }
    }

    @usableFromInline
    internal func recordSerializationMessageInbound(_ path: ActorPath, _ bytes: Int) {
        if path.starts(with: .userRoot) {
            self.serializationUserInboundMsgSize.record(bytes)
        } else if path.starts(with: .systemRoot) {
            self.serializationSystemInboundMsgSize.record(bytes)
        }
    }
}
