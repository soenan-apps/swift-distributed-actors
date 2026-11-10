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

import CoreMetrics
import DistributedActorsConcurrencyHelpers
import Logging
import NIO
import SWIM

extension ClusterShell {
    internal func recordMetrics(_ metrics: ClusterSystemMetrics, membership: Cluster.Membership) {
        metrics.recordMembership(membership)
        self.associationsLock.withLockVoid {
            metrics.clusterAssociationTombstones.record(self.associationTombstones.count)
        }
    }
}
