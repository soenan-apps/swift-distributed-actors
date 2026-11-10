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
// MARK: Cluster.Node

extension Cluster {
    /// A _unique_ node which includes also the node's unique `UID` which is used to disambiguate
    /// multiple incarnations of a system on the same host/port part -- similar to how an `ActorIncarnation`
    /// is used on the per-actor level.
    ///
    /// ### Implementation details
    /// The unique address of a remote node can only be obtained by performing the handshake with it.
    /// Once the remote node accepts our handshake, it offers the other node its unique address.
    /// Only once this address has been obtained can a node communicate with actors located on the remote node.
    public struct Node: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, Comparable {
        /// Transport address at which this node can be reached.
        public var endpoint: Cluster.Endpoint
        /// Unique identifier distinguishing incarnations at the same address.
        public let nid: Cluster.NodeID

        /// Human-readable system name of the endpoint.
        public var systemName: String {
            get {
                self.endpoint.systemName
            }
            set {
                self.endpoint.systemName = newValue
            }
        }

        /// Hostname or address of the endpoint.
        public var host: String {
            get {
                self.endpoint.host
            }
            set {
                self.endpoint.host = newValue
            }
        }

        /// Port of the endpoint.
        public var port: Int {
            get {
                self.endpoint.port
            }
            set {
                self.endpoint.port = newValue
            }
        }

        /// Human-readable endpoint address.
        public var description: String {
            "\(self.endpoint)"
        }

        /// Endpoint address including the unique node identifier.
        public var debugDescription: String {
            let address: Cluster.Endpoint = self.endpoint
            return "\(address.protocol)://\(address.systemName):\(self.nid)@\(address.host):\(address.port)"
        }

        /// Creates a node with a positive-port endpoint and an incarnation identifier.
        public init(endpoint: Cluster.Endpoint, nid: Cluster.NodeID) {
            precondition(endpoint.port > 0, "port MUST be > 0")
            self.endpoint = endpoint
            self.nid = nid
        }

        /// Creates a node using an explicit transport protocol.
        public init(protocol: String, systemName: String, host: String, port: Int, nid: Cluster.NodeID) {
            self.init(
                endpoint: Cluster.Endpoint(protocol: `protocol`, systemName: systemName, host: host, port: port),
                nid: nid
            )
        }

        /// Creates a node using the `sact` transport protocol.
        public init(systemName: String, host: String, port: Int, nid: Cluster.NodeID) {
            self.init(protocol: "sact", systemName: systemName, host: host, port: port, nid: nid)
        }

        /// Compares incarnation identifiers and endpoint addresses.
        public static func == (lhs: Cluster.Node, rhs: Cluster.Node) -> Bool {
            lhs.nid == rhs.nid && lhs.endpoint == rhs.endpoint
        }

        /// Orders nodes by endpoint, then incarnation identifier.
        public static func < (lhs: Cluster.Node, rhs: Cluster.Node) -> Bool {
            if lhs.endpoint == rhs.endpoint {
                return lhs.nid < rhs.nid
            }
            return lhs.endpoint < rhs.endpoint
        }
    }
}
