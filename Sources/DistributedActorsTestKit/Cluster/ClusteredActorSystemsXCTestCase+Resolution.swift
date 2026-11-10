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

import DistributedActorsConcurrencyHelpers
import Foundation
import Logging
import SWIM
import XCTest

@testable import DistributedCluster

extension ClusteredActorSystemsXCTestCase {
    /// Resolves the same actor identity as a remote reference on the supplied system.
    public func resolveRef<M>(
        _ system: ClusterSystem,
        type _: M.Type,
        id: ActorID,
        on targetSystem: ClusterSystem
    ) -> ActorRef<M> {
        // DO NOT TRY THIS AT HOME; we do this since we have no receptionist which could offer us references
        // first we manually construct the "right remote path", DO NOT ABUSE THIS IN REAL CODE (please) :-)
        let remoteNode: Cluster.Node = targetSystem.settings.bindNode
        let uniqueRemoteNode: ActorID = ActorID(remote: remoteNode, path: id.path, incarnation: id.incarnation)
        let resolveContext: ResolveContext<M> = ResolveContext<M>(id: uniqueRemoteNode, system: system)
        return system.resolve(context: resolveContext)
    }
}
