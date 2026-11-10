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
import Foundation

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Cluster.Endpoint

extension Cluster {
    /// An `Endpoint` is a triplet of protocol, host and port that a node is bound to.
    ///
    /// Unlike `Cluster.Node`, this address does not identify an actor system incarnation.
    /// During a handshake, discovering the remote node identifier upgrades the endpoint to a `Cluster.Node`.
    ///
    /// ### System name / human readable name
    /// The `systemName` is NOT taken into account when comparing nodes. It is only used for human readability
    /// and debugging and participates neither in hashcode nor equality of a `Node`, which is meant
    /// to represent any unique node that can live on specific host & port. System names are useful for human operators,
    /// using a naming scheme, such as one adopted from a cloud provider, to map nodes in actor system logs
    /// to other external systems.
    ///
    /// - SeeAlso: For more details on unique node ids, refer to: ``Cluster/Node-struct``.
    public struct Endpoint: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, Comparable {
        /// Transport protocol used to reach the node.
        public var `protocol`: String
        /// Human-readable system name, excluded from identity comparisons.
        public var systemName: String
        /// Hostname or address to contact.
        public var host: String
        /// Positive port number on which the node listens.
        public var port: Int

        /// Human-readable transport address including the system name.
        public var description: String {
            "\(self.protocol)://\(self.systemName)@\(self.host):\(self.port)"
        }

        /// The same transport address used by `description`.
        public var debugDescription: String {
            self.description
        }

        /// Creates an endpoint with an explicit transport protocol and a positive port.
        public init(protocol: String, systemName: String, host: String, port: Int) {
            precondition(port > 0, "port MUST be > 0")
            self.protocol = `protocol`
            self.systemName = systemName
            self.host = host
            self.port = port
        }

        /// Creates an endpoint using the `sact` transport protocol.
        public init(systemName: String, host: String, port: Int) {
            self.init(protocol: "sact", systemName: systemName, host: host, port: port)
        }

        /// Creates an unnamed endpoint using the `sact` transport protocol.
        public init(host: String, port: Int) {
            self.init(protocol: "sact", systemName: "", host: host, port: port)
        }

        /// Orders endpoints by transport address, excluding the human-readable system name.
        public static func < (lhs: Cluster.Endpoint, rhs: Cluster.Endpoint) -> Bool {
            "\(lhs.protocol)\(lhs.host)\(lhs.port)" < "\(rhs.protocol)\(rhs.host)\(rhs.port)"
        }

        /// Compares transport addresses, excluding the human-readable system name.
        public static func == (lhs: Cluster.Endpoint, rhs: Cluster.Endpoint) -> Bool {
            lhs.protocol == rhs.protocol && lhs.host == rhs.host && lhs.port == rhs.port
        }

        /// Hashes the transport address, excluding the human-readable system name.
        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.protocol)
            hasher.combine(self.host)
            hasher.combine(self.port)
        }

    }
}
