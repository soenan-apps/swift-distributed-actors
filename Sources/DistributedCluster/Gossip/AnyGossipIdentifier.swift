// SPDX-License-Identifier: Apache-2.0

internal struct AnyGossipIdentifier: Hashable, GossipIdentifier {
    internal let underlying: GossipIdentifier

    internal var gossipIdentifier: String {
        self.underlying.gossipIdentifier
    }

    internal var asAnyGossipIdentifier: Self {
        self
    }

    internal init(_ id: String) {
        self.underlying = StringGossipIdentifier(stringLiteral: id)
    }

    internal init(_ identifier: GossipIdentifier) {
        if let any = identifier as? Self {
            self = any
        } else {
            self.underlying = identifier
        }
    }

    internal static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.underlying.gossipIdentifier == rhs.underlying.gossipIdentifier
    }

    internal func hash(into hasher: inout Hasher) {
        self.underlying.gossipIdentifier.hash(into: &hasher)
    }
}
