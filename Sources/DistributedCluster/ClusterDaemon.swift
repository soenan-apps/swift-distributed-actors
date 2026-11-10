// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

/// Handle for a cluster daemon's actor system and lifecycle.
public struct ClusterDaemon {
    /// Default loopback endpoint used by the daemon.
    public static let defaultEndpoint: Cluster.Endpoint = Cluster.Endpoint(host: "127.0.0.1", port: 3_137)

    /// Actor system hosting the daemon.
    public let system: ClusterSystem

    /// Current settings of the daemon's actor system.
    public var settings: ClusterSystemSettings {
        self.system.settings
    }

    /// Suspends until the actor system terminates.
    public var terminated: Void {
        get async throws {
            try await self.system.terminated
        }
    }

    /// Whether the actor system has successfully terminated.
    public var isTerminated: Bool {
        self.system.isTerminated
    }

    /// Wraps an existing actor system as a cluster daemon.
    public init(system: ClusterSystem) {
        self.system = system
    }

    /// Stops the actor system and returns a handle for awaiting shutdown completion.
    @discardableResult
    public func shutdown() throws -> ClusterSystem.Shutdown {
        try self.system.shutdown()
    }
}
