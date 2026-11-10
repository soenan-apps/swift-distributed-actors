// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

extension Cluster {
    /// Unique incarnation identifier for a cluster node.
    public struct NodeID: Hashable, Sendable, Comparable, CustomStringConvertible {
        internal let value: UInt64

        /// Decimal representation of the node identifier.
        public var description: String {
            "\(self.value)"
        }

        /// Creates an identifier from its unsigned wire value.
        public init(_ value: UInt64) {
            self.value = value
        }

        /// Creates a nonzero random node identifier.
        public static func random() -> Cluster.Node.Identifier {
            Cluster.Node.Identifier(UInt64.random(in: 1 ... .max))
        }

        /// Orders node identifiers by their unsigned wire values.
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.value < rhs.value
        }
    }
}
