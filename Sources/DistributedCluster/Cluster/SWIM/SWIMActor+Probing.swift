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

extension SWIMActor {
    internal func sendPingRequests(_ directive: SWIMInstance.SendPingRequestDirective) async {
        let started: DispatchTime = .now()
        let firstTimer: CoreMetrics.Timer = self.metrics.shell.pingRequestResponseTimeFirst
        let firstResponse: SWIM.PingResponse? = await withTaskGroup(
            of: SWIM.PingResponse.self, returning: SWIM.PingResponse?.self
        ) { group in
            for detail in directive.requestDetails {
                group.addTask {
                    await self.sendPingRequest(detail, target: directive.target, timeout: directive.timeout)
                }
            }
            var firstSuccessful: SWIM.PingResponse?
            for await response in group {
                self.handleEveryPingRequestResponse(response: response, pinged: directive.target)
                if case .ack = response, firstSuccessful == nil {
                    firstTimer.recordInterval(since: started)
                    firstSuccessful = response
                }
            }
            return firstSuccessful
        }
        let response: SWIM.PingResponse = firstResponse ?? .timeout(
            target: directive.target, pingRequestOrigin: self.swimNode, timeout: directive.timeout, sequenceNumber: 0
        )
        self.handlePingRequestResponse(response: response, pinged: directive.target)
    }

    internal func sendPingRequest(
        _ detail: SWIMInstance.SendPingRequestDirective.PingRequestDetail,
        target: ClusterMembership.Node,
        timeout: Duration
    ) async -> SWIM.PingResponse {
        let peer: ClusterMembership.Node = detail.peerToPingRequestThrough
        let payload: SWIM.GossipPayload = detail.payload
        let sequenceNumber: SWIM.SequenceNumber = detail.sequenceNumber
        let metadata: Logger.Metadata = self.swim.metadata
        self.log.trace("Sending ping request for [\(target)] to [\(peer)] with payload: \(payload)")
        let started: DispatchTime = .now()
        self.metrics.shell.messageOutboundCount.increment()
        do {
            let peerActor: SWIMActor = peer.swimShell(self.actorSystem)
            let response: SWIM.PingResponse = try await peerActor.pingRequest(
                target: target, payload: payload, from: self.swimNode, timeout: timeout, sequenceNumber: sequenceNumber
            )
            self.metrics.shell.pingRequestResponseTimeAll.recordInterval(since: started)
            return response
        } catch {
            var failureMetadata: Logger.Metadata = metadata
            failureMetadata["swim/pingRequest/target"] = "\(target)"
            failureMetadata["swim/pingRequest/peerToPingRequestThrough"] = "\(peer)"
            failureMetadata["swim/pingRequest/sequenceNumber"] = "\(sequenceNumber)"
            failureMetadata["error"] = "\(error)"
            self.log.debug(".pingRequest resulted in error", metadata: failureMetadata)
            self.log.trace("Failed pingRequest", metadata: [
                "swim/target": "\(target)",
                "swim/payload": "\(payload)",
                "swim/pingTimeout": "\(timeout)",
                "error": "\(error)",
            ])
            return .timeout(
                target: target, pingRequestOrigin: self.swimNode, timeout: timeout, sequenceNumber: sequenceNumber
            )
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Message handlers and helpers

    // If `sendPing` is invoked without `pingRequestOrigin`, the result of this response handler can be ignored.
    // Otherwise, we might need to send ack/nack response to `pingRequestOrigin`, so it is the result of this
    // method that should be propagated, not the original ping response.
    internal func handlePingResponse(
        response: SWIM.PingResponse,
        pingRequestOrigin: ClusterMembership.Node?,
        pingRequestSequenceNumber: SWIM.SequenceNumber?
    ) -> SWIM.PingResponse {
        var pingRequestOriginResponse: SWIM.PingResponse?

        let directives: [SWIMInstance.PingResponseDirective] = self.swim.onPingResponse(
            response: response,
            pingRequestOrigin: pingRequestOrigin,
            pingRequestSequenceNumber: pingRequestSequenceNumber
        )
        for directive in directives {
            switch directive {
            case .gossipProcessed(let gossipDirective):
                self.handleGossipPayloadProcessedDirective(gossipDirective)

            case let .sendAck(_, acknowledging, target, incarnation, payload):  // only if pingRequestOrigin != nil
                pingRequestOriginResponse = .ack(
                    target: target, incarnation: incarnation, payload: payload, sequenceNumber: acknowledging
                )

            case let .sendNack(_, acknowledging, target):  // only if pingRequestOrigin != nil
                pingRequestOriginResponse = .nack(target: target, sequenceNumber: acknowledging)

            case .sendPingRequests(let pingRequestDirective):
                Task {
                    await self.sendPingRequests(pingRequestDirective)
                }
            }
        }

        return pingRequestOriginResponse ?? response
    }

    internal func handlePingRequestResponse(response: SWIM.PingResponse, pinged: ClusterMembership.Node) {
        // self.tracelog(context, .receive(pinged: pinged), message: response)
        let directives: [SWIMInstance.PingRequestResponseDirective] = self.swim.onPingRequestResponse(
            response,
            pinged: pinged
        )
        for directive in directives {
            switch directive {
            case .gossipProcessed(let gossipDirective):
                self.handleGossipPayloadProcessedDirective(gossipDirective)

            case .alive(let previousStatus):
                self.log.debug("Member [\(pinged)] is alive")
                if previousStatus.isUnreachable, let member = swim.member(for: pinged) {
                    // member was unreachable but now is alive, we should emit an event
                    let event: SWIM.MemberStatusChangedEvent = SWIM.MemberStatusChangedEvent(
                        previousStatus: previousStatus, member: member
                    )
                    self.tryAnnounceMemberReachability(change: event)
                }

            case .newlySuspect:
                self.log.debug("Member [\(pinged)] marked as suspect")

            case .nackReceived:
                self.log.debug("Received `nack` from indirect probing of [\(pinged)]")

            default:
                ()
            }
        }
    }

    /// Announce to the `ClusterShell` a change in reachability of a member.
    internal func tryAnnounceMemberReachability(change: SWIM.MemberStatusChangedEvent?) {
        guard let change = change else {
            // this means it likely was a change to the same status or it was about us, so we do not need to announce
            // anything
            return
        }

        guard change.isReachabilityChange else {
            // the change is from a reachable to another reachable (or an unreachable to another unreachable-like (e.g.
            // dead) state),
            // and thus we must not act on it, as the shell was already notified before about the change into the
            // current status.
            //
            // if this is a move from unreachable -> down, then the downing subsystem will have already sent out the
            // down event,
            // and we should not duplicate it.
            return
        }

        // Log the transition
        switch change.status {
        case .unreachable:
            self.log.info(
                """
                Node \(change.member.node) determined [.unreachable]! \
                The node is not yet marked [.down]; a downing strategy or Cluster.Event subscriber may act on this.
                """,
                metadata: [
                    "swim/member": "\(change.member)"
                ]
            )

        default:
            self.log.info(
                "Node \(change.member.node) determined [.\(change.status)] (was \(optional: change.previousStatus)).",
                metadata: [
                    "swim/member": "\(change.member)"
                ]
            )
        }

        // If SWIM claims we are dead, ignore this; we should be informed about this in high-level gossip soon enough.
        if change.status == .dead,
            change.member.node.asClusterNode == self.id.node {
            return
        }

        let reachability: Cluster.MemberReachability
        switch change.status {
        case .alive, .suspect:
            reachability = .reachable

        case .unreachable, .dead:
            reachability = .unreachable
        }

        guard let node = change.member.node.asClusterNode else {
            self.log.warning(
                """
                Unable to emit failureDetectorReachabilityChanged, for event: \(change), \
                since can't represent member as node!
                """
            )
            return
        }

        self.clusterRef.tell(.command(.failureDetectorReachabilityChanged(node, reachability)))
    }

    internal func handleGossipPayloadProcessedDirective(_ directive: SWIM.Instance.GossipProcessedDirective) {
        switch directive {
        case .applied(let change):
            self.tryAnnounceMemberReachability(change: change)
        }
    }

    /// We have to handle *every* response, because they adjust the value of the timeouts we'll be using in future
    /// probes.
    internal func handleEveryPingRequestResponse(response: SWIM.PingResponse, pinged: ClusterMembership.Node) {
        // self.tracelog(.receive(pinged: pinged.node), message: "\(response)")
        let directives: [SWIMInstance.PingRequestResponseDirective] = self.swim.onEveryPingRequestResponse(
            response, pinged: pinged
        )

        if !directives.isEmpty {
            fatalError(
                """
                Ignored directive from: onEveryPingRequestResponse! \
                This directive used to be implemented as always returning no directives. \
                Check your shell implementations if you updated the SWIM library as it seems this has changed. \
                Directive was: \(directives), swim was: \(self.swim.metadata)
                """
            )
        }
    }

}
