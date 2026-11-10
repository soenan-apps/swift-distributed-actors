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

import ClusterMembership
import CoreMetrics
import Distributed
import Logging
import NIOCore
import SWIM

import struct Dispatch.DispatchTime

/// The SWIM shell is responsible for driving all interactions of the `SWIM.Instance` with the outside world.
///
/// - SeeAlso: `SWIM.Instance` for detailed documentation about the SWIM protocol implementation.
internal distributed actor SWIMActor: CustomStringConvertible {
    internal typealias ActorSystem = ClusterSystem
    internal typealias SWIMInstance = SWIM.Instance

    internal static let name: String = "swim"

    internal static var props: Props {
        var spawnProps: Props = Props()
        spawnProps.knownActorName = ActorPath.swimPath.name
        spawnProps.wellKnown = true
        return spawnProps.metrics(group: "swim.shell", measure: [.serialization, .deserialization])
    }

    internal let settings: SWIM.Settings
    internal let clusterRef: ClusterShell.Ref

    internal lazy var swim: SWIM.Instance = SWIMInstance(
        settings: self.customizeSWIMSettings(self.settings), myself: self.swimNode
    )

    nonisolated internal var swimNode: ClusterMembership.Node {
        .init(
            protocol: self.id.node.endpoint.protocol,
            host: self.id.node.host,
            port: self.id.node.port,
            uid: self.id.node.nid.value
        )
    }

    internal lazy var log: Logger = {
        var logger: Logger = Logger(actor: self)
        logger.logLevel = settings.logger.logLevel
        return logger
    }()

    internal var metrics: SWIM.Metrics {
        self.swim.metrics
    }

    nonisolated internal var description: String {
        "\(Self.self)(\(self.id))"
    }

    internal init(settings: SWIM.Settings, clusterRef: ClusterShell.Ref, system: ActorSystem) async {
        self.settings = settings
        self.clusterRef = clusterRef
        self.actorSystem = system

        self.onStart()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Initialization helpers

    /// Applies some default changes to the SWIM settings.
    internal func customizeSWIMSettings(_ settings: SWIM.Settings) -> SWIM.Settings {
        var customizedSettings: SWIM.Settings = settings
        customizedSettings.logger = self.log
        customizedSettings.metrics.systemName = self.actorSystem.settings.metrics.systemName
        return customizedSettings
    }

    /// Initialize timers and other after-initialized tasks
    internal func onStart() {
        precondition(
            self.id.incarnation == 0 || self.id.isWellKnown,
            "SWIM was not well known!? Was: \(self.id.detailedDescription)"
        )
        guard self.settings.initialContactPoints.isEmpty else {
            fatalError(
                """
                swim.initialContactPoints was not empty! Please use `settings.discovery` settings to discover peers,
                rather than the internal swim instances configuration settings!
                """
            )
        }
        self.handlePeriodicProtocolPeriodTick()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Periodic Protocol Ticks

    /// Scheduling a new protocol period and performing the actions for the current protocol period
    internal func handlePeriodicProtocolPeriodTick() {
        for directive in self.swim.onPeriodicPingTick() {
            switch directive {
            case .membershipChanged(let change):
                self.tryAnnounceMemberReachability(change: change)

            case let .sendPing(target, payload, timeout, sequenceNumber):
                self.log.trace(
                    "Periodic ping random member, among: \(self.swim.otherMemberCount)", metadata: self.swim.metadata
                )
                Task {
                    await self.sendPing(
                        to: target,
                        payload: payload,
                        request: (origin: nil, sequenceNumber: nil),
                        timeout: timeout,
                        sequenceNumber: sequenceNumber
                    )
                }

            case .scheduleNextTick(let delay):
                // Keep scheduling the timer so that it fires for each tick
                Task {
                    do {
                        try await Task.sleep(until: .now + .nanoseconds(delay.nanoseconds), clock: .continuous)
                    } catch {
                        return // Task.sleep throws when this scheduled tick is cancelled.
                    }
                    self.handlePeriodicProtocolPeriodTick()
                }
            }
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Send ping, ping-req

    @discardableResult
    internal func sendPing(
        to target: ClusterMembership.Node,
        payload _: SWIM.GossipPayload,
        request: (origin: ClusterMembership.Node?, sequenceNumber: SWIM.SequenceNumber?),
        timeout: Duration,
        sequenceNumber: SWIM.SequenceNumber
    ) async -> SWIM.PingResponse {
        let payload: SWIM.GossipPayload = self.swim.makeGossipPayload(to: target)
        let targetPeer: SWIMActor = target.swimShell(self.actorSystem)

        self.log.debug(
            "Sending ping",
            metadata: self.swim.metadata([
                "swim/target": "\(target)",
                "swim/gossip/payload": "\(payload)",
                "swim/timeout": "\(timeout)",
            ])
        )

        let pingSentAt: DispatchTime = DispatchTime.now()
        self.metrics.shell.messageOutboundCount.increment()

        do {
            let pingResponse: SWIM.PingResponse = try await targetPeer.ping(
                payload: payload, from: self.swimNode, timeout: timeout, sequenceNumber: sequenceNumber
            )
            self.metrics.shell.pingResponseTime.recordInterval(since: pingSentAt)
            return self.handlePingResponse(
                response: pingResponse,
                pingRequestOrigin: request.origin,
                pingRequestSequenceNumber: request.sequenceNumber
            )
        } catch {
            self.log.debug(
                ".ping resulted in error",
                metadata: self.swim.metadata([
                    "swim/ping/target": "\(target)",
                    "swim/ping/sequenceNumber": "\(sequenceNumber)",
                    "error": "\(error)",
                ])
            )
            return self.handlePingResponse(
                response: .timeout(
                    target: target,
                    pingRequestOrigin: request.origin,
                    timeout: timeout,
                    sequenceNumber: sequenceNumber
                ),
                pingRequestOrigin: request.origin,
                pingRequestSequenceNumber: request.sequenceNumber
            )
        }
    }

    internal func monitor(node: Cluster.Node) {
        guard self.actorSystem.cluster.node.endpoint != node.endpoint else {
            return // Do not monitor this node or its replacement.
        }

        self.sendFirstRemotePing(on: node)
    }

    nonisolated internal func confirmDead(node: Cluster.Node) {
        Task {
            await self.whenLocal { myself in
                let directive: SWIMInstance.ConfirmDeadDirective = myself.swim.confirmDead(node: node.asSWIMNode)
                switch directive {
                case .applied(let change):
                    myself.log.warning(
                        "Confirmed node .dead: \(change)",
                        metadata: myself.swim.metadata(["swim/change": "\(change)"])
                    )

                case .ignored:
                    return
                }
            }
        }
    }

    /// This is effectively joining the SWIM membership of the other member.
    internal func sendFirstRemotePing(on targetUniqueNode: Cluster.Node) {
        let targetNode: ClusterMembership.Node = ClusterMembership.Node(node: targetUniqueNode)

        let fakeGossip: SWIM.GossipPayload = SWIM.GossipPayload.membership([
            SWIM.Member(node: targetNode, status: .alive(incarnation: 0), protocolPeriod: 0)
        ])
        _ = self.swim.onPingResponse(
            response: .ack(target: targetNode, incarnation: 0, payload: fakeGossip, sequenceNumber: 0),
            pingRequestOrigin: nil,
            pingRequestSequenceNumber: nil
        )

        Task {
            await self.sendPing(
                to: targetNode,
                payload: swim.makeGossipPayload(to: nil),
                request: (origin: nil, sequenceNumber: nil),
                timeout: .seconds(1),
                sequenceNumber: self.swim.nextSequenceNumber()
            )
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: For testing only

    internal func membershipState() -> [SWIM.Member] {
        Array(self.swim.members)
    }

    internal func configureSWIM(_ configure: (inout SWIM.Instance) throws -> Void) rethrows {
        try configure(&self.swim)
    }

}
