// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

/// Typed identifier of a cluster plugin and its optional sub-plugin.
public struct PluginKey<P: Plugin>: CustomStringConvertible, ExpressibleByStringLiteral, Sendable {
    public let plugin: String
    public let sub: String?

    internal var asAny: AnyPluginKey { AnyPluginKey(self) }

    public var description: String {
        if let sub = self.sub {
            return "PluginKey<\(P.self)>(\(self.plugin), sub: \(sub))"
        }
        return "PluginKey<\(P.self)>(\(self.plugin))"
    }

    public init(id plugin: String) {
        self.init(plugin: plugin, sub: nil)
    }

    public init(stringLiteral: StringLiteralType) {
        self.init(id: stringLiteral)
    }

    private init(plugin: String, sub: String?) {
        self.plugin = plugin
        self.sub = sub
    }

    public func makeSub(_ sub: String) -> Self {
        precondition(self.sub == nil, "Cannot make a sub plugin key from \(self) (sub MUST be nil)")
        return .init(plugin: self.plugin, sub: sub)
    }
}
