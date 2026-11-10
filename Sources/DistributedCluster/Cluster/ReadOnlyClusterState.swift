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
import Logging
import NIO

internal protocol ReadOnlyClusterState {
    var log: Logger { get }
    var allocator: ByteBufferAllocator { get }
    var eventLoopGroup: EventLoopGroup { get }

    /// Base backoff strategy to use in handshake retries
    var handshakeBackoff: BackoffStrategy { get }

    /// Unique address of the current node.
    var selfNode: Cluster.Node { get }
    var selfMember: Cluster.Member { get }

    var settings: ClusterSystemSettings { get }
}
