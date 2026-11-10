// SPDX-License-Identifier: Apache-2.0

/// Used to identify which identity a payload is tied with.
/// E.g. it could be used to mark the CRDT instance the gossip is carrying, or which "entity" a gossip relates to.
internal protocol GossipIdentifier {
    var gossipIdentifier: String { get }

    var asAnyGossipIdentifier: AnyGossipIdentifier { get }

    init(_ gossipIdentifier: String)
}
