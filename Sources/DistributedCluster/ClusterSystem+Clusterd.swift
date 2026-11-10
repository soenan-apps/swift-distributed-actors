// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Atomics
import Backtrace
import CDistributedActorsMailbox
import Dispatch
import Distributed
import DistributedActorsConcurrencyHelpers
import Foundation  // for UUID
import Logging
import NIO

extension ClusterSystem {
    /// Starts a cluster daemon at its default endpoint, applying additional settings before startup.
    public static func startClusterDaemon(
        configuredWith configureSettings: sending (inout ClusterSystemSettings) -> Void = { _ in () }
    ) async -> ClusterDaemon {
        let system: ClusterSystem = await ClusterSystem("clusterd") { settings in
            settings.endpoint = ClusterDaemon.defaultEndpoint
            configureSettings(&settings)
        }

        return ClusterDaemon(system: system)
    }
}
