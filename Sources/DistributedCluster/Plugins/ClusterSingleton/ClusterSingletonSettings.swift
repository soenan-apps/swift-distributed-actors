// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

/// Settings for a `ClusterSingleton`.
public struct ClusterSingletonSettings: Sendable {
    /// Retry timing for finding the currently active singleton.
    public struct LocateActiveSingletonBackoffSettings: Sendable {
        internal var initialInterval: Duration = .milliseconds(300)
        internal var multiplier: Double = ExponentialBackoffStrategy.Defaults.multiplier
        internal var capInterval: Duration = ExponentialBackoffStrategy.Defaults.capInterval
        internal var randomFactor: Double = ExponentialBackoffStrategy.Defaults.randomFactor
        internal var maxAttempts: Int = 5
    }

    /// Unique name for the singleton, used to identify the conceptual singleton in the cluster.
    /// E.g. there is always one "boss" instance in the cluster, regardless where it is incarnated.
    ///
    /// Set when creating a singleton reference with `host` or `proxy`.
    public internal(set) var name: String = ""

    /// Capacity of temporary message buffer in case singleton is unavailable.
    /// If the buffer becomes full, the *oldest* messages would be disposed to make room for the newer messages.
    public var bufferCapacity: Int = 2_048 {
        willSet(newValue) {
            precondition(newValue > 0, "bufferCapacity must be greater than 0")
        }
    }

    /// Controls allocation of the node on which the singleton runs.
    public var allocationStrategy: SingletonAllocationSettings = .byLeadership

    /// Time to wait for the singleton, whether allocated on this node or another, before
    /// we stop stashing calls and throw error.
    public var allocationTimeout: Duration = .seconds(30)

    /// Backoff used while locating an active singleton.
    public var locateActiveSingletonBackoff: LocateActiveSingletonBackoffSettings = .init()

    public init() {
        // Stored properties define the default singleton configuration.
    }
}
