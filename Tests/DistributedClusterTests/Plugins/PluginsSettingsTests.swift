// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedCluster
import XCTest

internal final class PluginsSettingsTests: XCTestCase {
    internal func test_pluginsSettings_isInstalled() {
        var pluginsSettings: PluginsSettings = PluginsSettings()

        let clusterSingletonPlugin: ClusterSingletonPlugin = ClusterSingletonPlugin()
        XCTAssertFalse(pluginsSettings.isInstalled(plugin: clusterSingletonPlugin))

        pluginsSettings.install(plugin: clusterSingletonPlugin)
        XCTAssertTrue(pluginsSettings.isInstalled(plugin: clusterSingletonPlugin))
    }
}
