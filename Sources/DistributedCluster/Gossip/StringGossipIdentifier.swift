// SPDX-License-Identifier: Apache-2.0

internal struct StringGossipIdentifier:
    GossipIdentifier, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    internal let gossipIdentifier: String

    internal var asAnyGossipIdentifier: AnyGossipIdentifier {
        AnyGossipIdentifier(self)
    }

    internal var description: String {
        "StringGossipIdentifier(\(self.gossipIdentifier))"
    }

    internal init(_ gossipIdentifier: StringLiteralType) {
        self.gossipIdentifier = gossipIdentifier
    }

    internal init(stringLiteral gossipIdentifier: StringLiteralType) {
        self.gossipIdentifier = gossipIdentifier
    }
}
