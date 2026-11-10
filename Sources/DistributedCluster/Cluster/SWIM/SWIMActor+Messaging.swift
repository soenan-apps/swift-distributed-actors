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
    nonisolated internal func ping(
        payload: SWIM.GossipPayload,
        from pingOrigin: ClusterMembership.Node,
        timeout: Duration,
        sequenceNumber: SWIM.SequenceNumber
    ) async throws -> SWIM.PingResponse {
        try await RemoteCall.with(timeout: .nanoseconds(timeout.nanoseconds)) {
            let response: SWIM.PingResponse = try await self.ping(
                origin: pingOrigin, payload: payload, sequenceNumber: sequenceNumber
            )
            if case .nack = response {
                throw SWIMActorError.illegalMessageType("Unexpected .nack reply to .ping message! Was: \(response)")
            }
            return response
        }
    }

    internal distributed func ping(
        origin: ClusterMembership.Node,
        payload: SWIM.GossipPayload,
        sequenceNumber: SWIM.SequenceNumber
    ) throws -> SWIM.PingResponse {
        self.log.trace(
            "Received ping@\(sequenceNumber)",
            metadata: self.swim.metadata([
                "swim/ping/origin": "\(origin)",
                "swim/ping/payload": "\(payload)",
                "swim/ping/seqNr": "\(sequenceNumber)",
            ])
        )
        self.metrics.shell.messageInboundCount.increment()

        for directive in self.swim.onPing(
            pingOrigin: origin,
            payload: payload,
            sequenceNumber: sequenceNumber
        ) {
            switch directive {
            case .gossipProcessed(let gossipDirective):
                self.handleGossipPayloadProcessedDirective(gossipDirective)

            case let .sendAck(_, pingedTarget, incarnation, payload, sequenceNumber):
                return .ack(
                    target: pingedTarget, incarnation: incarnation, payload: payload, sequenceNumber: sequenceNumber
                )
            }
        }

        assertionFailure("ping should always return ack")

        throw SWIMActorError.noResponse
    }

    nonisolated internal func pingRequest(
        target: ClusterMembership.Node,
        payload: SWIM.GossipPayload,
        from pingRequestOrigin: ClusterMembership.Node,
        timeout: Duration,
        sequenceNumber: SWIM.SequenceNumber
    ) async throws -> SWIM.PingResponse {
        try await RemoteCall.with(timeout: .nanoseconds(timeout.nanoseconds)) {
            try await self.pingRequest(
                target: target,
                pingRequestOrigin: pingRequestOrigin,
                payload: payload,
                sequenceNumber: sequenceNumber
            )
        }
    }

    internal distributed func pingRequest(
        target: ClusterMembership.Node,
        pingRequestOrigin: ClusterMembership.Node,
        payload: SWIM.GossipPayload,
        sequenceNumber pingRequestSequenceNumber: SWIM.SequenceNumber
    ) async throws -> SWIM.PingResponse {
        self.log.trace(
            "Received pingRequest@\(pingRequestSequenceNumber) [\(target)] from [\(pingRequestOrigin)]",
            metadata: self.swim.metadata([
                "swim/pingRequest/origin": "\(pingRequestOrigin)",
                "swim/pingRequest/payload": "\(payload)",
                "swim/pingRequest/seqNr": "\(pingRequestSequenceNumber)",
            ])
        )
        self.metrics.shell.messageInboundCount.increment()

        for directive in self.swim.onPingRequest(
            target: target,
            pingRequestOrigin: pingRequestOrigin,
            payload: payload,
            sequenceNumber: pingRequestSequenceNumber
        ) {
            switch directive {
            case .gossipProcessed(let gossipDirective):
                self.handleGossipPayloadProcessedDirective(gossipDirective)

            case let .sendPing(target, payload, requestOrigin, requestNumber, timeout, pingSequenceNumber):
                return await self.sendPing(
                    to: target,
                    payload: payload,
                    request: (origin: requestOrigin, sequenceNumber: requestNumber),
                    timeout: timeout,
                    sequenceNumber: pingSequenceNumber
                )
            }
        }

        assertionFailure("pingRequest should always return ack/nack from sendPing")

        throw SWIMActorError.noResponse
    }

}
