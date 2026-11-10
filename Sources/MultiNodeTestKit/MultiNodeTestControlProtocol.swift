// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedCluster
import OrderedCollections

/// Runtime state installed by the runner before a test body executes.
public protocol MultiNodeTestControlProtocol {
    /// Actor system running on the current node.
    var actorSystem: ClusterSystem? { get set }
    /// Conductor coordinating checkpoints.
    var conductorStorage: MultiNodeTestConductor? { get set }
    /// Endpoints indexed by node name.
    var endpointsByName: [String: Cluster.Endpoint] { get set }

    /// Returns every endpoint except the named node.
    func endpoints(except name: String) -> [Cluster.Endpoint]
}

extension MultiNodeTestControlProtocol {
    /// Returns every endpoint except the named node.
    public func endpoints(except nodeName: String) -> [Cluster.Endpoint] {
        self.endpointsByName.values.filter { $0.systemName != nodeName }
    }
}
