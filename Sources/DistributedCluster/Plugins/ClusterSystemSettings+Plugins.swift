// Copyright (c) 2019-2023 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

extension ClusterSystemSettings {
    /// Installs a plugin in this system's settings.
    public static func += <P: Plugin>(settings: inout ClusterSystemSettings, plugin: P) {
        settings.plugins.install(plugin: plugin)
    }
}
