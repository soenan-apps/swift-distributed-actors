// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

internal struct ReplicaID: Hashable, Comparable, CustomStringConvertible, Codable {
    internal enum Storage: Hashable {
        case actorID(ActorID)
        // case actorIdentity(ClusterSystem.ActorID)
        case node(Cluster.Node)
        case nodeID(Cluster.Node.Identifier)

        internal var isActorID: Bool {
            switch self {
            case .actorID:
                return true

            default:
                return false
            }
        }

        //        var isActorIdentity: Bool {
        //            switch self {
        //            case .actorIdentity: return true
        //            default: return false
        //            }
        //        }

        internal var isNode: Bool {
            switch self {
            case .node:
                return true

            default:
                return false
            }
        }

        internal var isNodeID: Bool {
            switch self {
            case .nodeID:
                return true

            default:
                return false
            }
        }
    }

    internal enum DiscriminatorKeys: String, Codable {
        case actorID = "a"
        case node = "N"
        case nodeID = "n"
    }

    internal enum CodingKeys: String, CodingKey {
        case discriminator = "_case"

        case value = "value"
    }

    internal let storage: Storage

    internal var description: String {
        switch self.storage {
        case .actorID(let id):
            return "actor:\(id)"

        case .node(let node):
            return "node:\(node)"

        case .nodeID(let nid):
            return "nodeID:\(nid)"
        }
    }

    internal init(_ representation: Storage) {
        self.storage = representation
    }

    internal init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: .discriminator) {
        case .actorID:
            self = try .actorID(container.decode(ActorID.self, forKey: .value))

        case .node:
            self = try .node(container.decode(Cluster.Node.self, forKey: .value))

        case .nodeID:
            self = try .nodeID(container.decode(UInt64.self, forKey: .value))
        }
    }

    internal static func actor<M: Codable>(_ context: ActorContext<M>) -> Self {
        .init(.actorID(context.id))
    }

    internal static func actorID(_ id: ActorID) -> Self {
        .init(.actorID(id))
    }

    internal static func node(_ node: Cluster.Node) -> Self {
        .init(.node(node))
    }

    internal static func nodeID(_ node: Cluster.Node) -> Self {
        .init(.nodeID(node.nid))
    }

    internal static func nodeID(_ nodeID: UInt64) -> Self {
        .init(.nodeID(.init(nodeID)))
    }

    internal static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case let (.actorID(left), .actorID(right)):
            return left < right

        case let (.node(left), .node(right)):
            return left < right

        case let (.nodeID(left), .nodeID(right)):
            return left < right

        case (.node, _), (.nodeID, _), (.actorID, _):
            return false
        }
    }

    internal static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case let (.actorID(left), .actorID(right)):
            return left == right

        case let (.node(left), .node(right)):
            return left == right

        case let (.nodeID(left), .nodeID(right)):
            return left == right

        case let (.node(left), .nodeID(right)):
            return left.nid == right

        case let (.nodeID(left), .node(right)):
            return left == right.nid

        case (.node, _), (.nodeID, _), (.actorID, _):
            return false
        }
    }

    internal func ensuringNode(_ node: Cluster.Node) -> Self {
        switch self.storage {
        case .actorID(let id):
            return .actorID(id)

        case .node(let existingNode):
            assert(
                existingNode.nid == node.nid,
                "Attempted to ensureNode with non-matching node identifier, was: \(existingNode)], attempted: \(node)"
            )
            return self

        case .nodeID(let nid):  // drops the nid
            assert(
                nid == node.nid,
                "Attempted to ensureNode with non-matching node identifier, was: \(nid)], attempted: \(node)"
            )
            return .node(node)
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        switch self.storage {
        case .actorID(let address):
            try container.encode(DiscriminatorKeys.actorID, forKey: .discriminator)
            try container.encode(address, forKey: .value)

        case .node(let node):
            try container.encode(DiscriminatorKeys.node, forKey: .discriminator)
            try container.encode(node, forKey: .value)

        case .nodeID(let nid):
            try container.encode(DiscriminatorKeys.nodeID, forKey: .discriminator)
            try container.encode(nid.value, forKey: .value)
        }
    }
}
