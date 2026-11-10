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

import Distributed
import DistributedActorsConcurrencyHelpers
import Foundation
import XCTest

@testable import DistributedCluster

internal final class ProbeQueue<Item> {
    internal let items: AsyncStream<Item>
    private let continuation: AsyncStream<Item>.Continuation

    internal init() {
        let stream: (stream: AsyncStream<Item>, continuation: AsyncStream<Item>.Continuation) = AsyncStream.makeStream()
        self.items = stream.stream
        self.continuation = stream.continuation
    }

    internal func enqueue(_ item: Item) {
        self.continuation.yield(item)
    }
}

internal distributed actor TestProbeInternal: LifecycleWatch {
    internal typealias ActorSystem = ClusterSystem

    internal let terminatedQueue: ProbeQueue<ActorID> = ProbeQueue<ActorID>()

    internal func terminated(actor id: ActorID) {
        self.terminatedQueue.enqueue(id)
    }
}
