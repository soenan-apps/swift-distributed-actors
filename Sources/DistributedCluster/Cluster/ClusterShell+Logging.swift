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

import Logging

extension ClusterShellState {
    internal enum TraceLogType: CustomStringConvertible {
        case inbound
        case outbound

        internal var description: String {
            switch self {
            case .inbound:
                return "IN"

            case .outbound:
                return "OUT"
            }
        }
    }

    /// Dumps cluster messages at the configured level, or warning when compile-time tracing is enabled.
    internal func tracelog<Message>(
        _ type: TraceLogType,
        message: Message,
        location: ClusterTraceLocation
    ) {
        let level: Logger.Level?
        #if SACT_TRACELOG_CLUSTER
        level = .warning
        #else
        switch type {
        case .outbound, .inbound:
            level = self.settings.traceLogLevel
        }
        #endif

        if let level = level {
            self.log.log(
                level: level,
                "[tracelog:cluster] \(type.description)(\(self.settings.endpoint.port)): \(message)",
                file: location.file,
                function: location.function,
                line: location.line
            )
        }
    }
}

extension ClusterShell {
    internal enum TraceLogType: CustomStringConvertible {
        case send(endpoint: Cluster.Endpoint)
        case receive(from: Cluster.Endpoint)
        case receiveUnique(from: Cluster.Node)
        case gossip(Cluster.MembershipGossip)

        internal var description: String {
            switch self {
            case .send(let endpoint):
                return "     SEND(to:\(endpoint))"

            case .receive(let endpoint):
                return "     RECV(from:\(endpoint))"

            case .gossip(let gossip):
                return "   GOSSIP(\(gossip))"

            case .receiveUnique(let node):
                return "RECV_UNIQ(from:\(node))"
            }
        }
    }

    /// Dumps cluster messages while preserving the original caller's source location.
    internal func tracelog<Message>(
        _ context: ActorContext<ClusterShell.Message>,
        _ type: TraceLogType,
        message: Message,
        location: ClusterTraceLocation
    ) {
        if let level = context.system.settings.traceLogLevel {
            context.log.log(
                level: level,
                "[tracelog:cluster] \(type.description): \(message)",
                file: location.file,
                function: location.function,
                line: location.line
            )
        }
    }
}
