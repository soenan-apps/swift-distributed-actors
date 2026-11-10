// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

extension ClusterSystem {
    /// Returns the installed cluster singleton plugin.
    public var singleton: ClusterSingletonPlugin {
        let key: ClusterSingletonPlugin.Key = ClusterSingletonPlugin.pluginKey
        guard let singletonPlugin = self.settings.plugins[key] else {
            fatalError("No plugin found for key: [\(key)], installed plugins: \(self.settings.plugins)")
        }
        return singletonPlugin
    }
}
