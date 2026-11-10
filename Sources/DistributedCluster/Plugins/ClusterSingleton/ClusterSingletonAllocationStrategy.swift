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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Protocol for singleton allocation strategy

/// Strategy for choosing a `Cluster.Node` to allocate singleton.
public protocol ClusterSingletonAllocationStrategy {
    /// The currently allocated node for the singleton.
    var node: Cluster.Node? { get async }

    /// Processes an event and returns the current singleton node.
    func onClusterEvent(_ clusterEvent: Cluster.Event) async -> Cluster.Node?

}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: ClusterSingletonAllocationStrategy implementations
