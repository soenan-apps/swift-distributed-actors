// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

internal struct AnyPluginKey: Hashable, CustomStringConvertible, Sendable {
    internal let pluginTypeId: ObjectIdentifier
    internal let plugin: String
    internal let sub: String?

    internal var description: String {
        if let sub = self.sub {
            return "AnyPluginKey(\(self.plugin), sub: \(sub))"
        }
        return "AnyPluginKey(\(self.plugin))"
    }

    internal init<P: Plugin>(_ key: PluginKey<P>) {
        self.pluginTypeId = ObjectIdentifier(P.self)
        self.plugin = key.plugin
        self.sub = key.sub
    }
}
