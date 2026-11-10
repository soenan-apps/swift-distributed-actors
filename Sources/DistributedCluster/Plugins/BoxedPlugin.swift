// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

internal struct BoxedPlugin: AnyPlugin {
    private let underlying: AnyPlugin
    internal let key: AnyPluginKey

    internal init<P: Plugin>(_ plugin: P) {
        self.underlying = plugin
        self.key = AnyPluginKey(plugin.key)
    }

    internal func unsafeUnwrapAs<P: Plugin>(_: P.Type) -> P {
        guard let unwrapped = self.underlying as? P else {
            fatalError("Type mismatch, expected: [\(String(reflecting: P.self))] got [\(self.underlying)]")
        }
        return unwrapped
    }

    internal func start(_ system: ClusterSystem) async throws {
        try await self.underlying.start(system)
    }

    internal func stop(_ system: ClusterSystem) async {
        await self.underlying.stop(system)
    }
}
