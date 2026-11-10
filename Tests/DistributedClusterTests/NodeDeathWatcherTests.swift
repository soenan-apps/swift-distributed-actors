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

import DistributedActorsTestKit
import Foundation
import SWIM
import XCTest

@testable import DistributedCluster

internal final class NodeDeathWatcherTests: ClusteredActorSystemsXCTestCase {
    internal func test_nodeDeath_shouldFailAllRefsOnSpecificAddress() async throws {
        let first: ClusterSystem = await setUpNode("first") { settings in
            settings.swim.probeInterval = .milliseconds(100)
        }
        let second: ClusterSystem = await setUpNode("second") { settings in
            settings.swim.probeInterval = .milliseconds(100)
        }

        try await self.joinNodes(node: first, with: second)

        let refOnRemote1: ActorRef<String> = try second.spawn("remote-1", .ignore)
        let refOnFirstToRemote1: ActorRef<String> = first.resolve(ref: refOnRemote1, onSystem: second)

        let refOnRemote2: ActorRef<String> = try second.spawn("remote-2", .ignore)
        let refOnFirstToRemote2: ActorRef<String> = first.resolve(ref: refOnRemote2, onSystem: second)

        let testKit: ActorTestKit = ActorTestKit(first)
        let probe: ActorTestProbe<Signals.Terminated> = testKit.makeTestProbe(expecting: Signals.Terminated.self)

        // --- prepare actor on [first], which watches remote actors ---

        _ = try first.spawn(
            "watcher1",

            Behavior<String>.setup { context in
                context.watch(refOnFirstToRemote1)
                context.watch(refOnFirstToRemote2)

                let recv: Behavior<String> = .receiveMessage { _ in
                    .same
                }

                return recv.receiveSpecificSignal(Signals.Terminated.self) { _, terminated in
                    probe.ref.tell(terminated)
                    return .same
                }
            }
        )

        try await self.ensureNodes(.operational, nodes: first.cluster.node, second.cluster.node)
        first.cluster.down(endpoint: second.cluster.node.endpoint)

        // should cause termination of all remote actors, observed by the local actors on [first]
        let termination1: Signals.Terminated = try probe.expectMessage()
        let termination2: Signals.Terminated = try probe.expectMessage()
        let terminations: [Signals.Terminated] = [termination1, termination2]
        terminations.shouldContain { terminated in
            (!terminated.existenceConfirmed) && terminated.id.name == "remote-1"
        }
        terminations.shouldContain { terminated in
            (!terminated.existenceConfirmed) && terminated.id.name == "remote-2"
        }

        // should not trigger terminated again for any of the remote refs
        first.cluster.down(endpoint: second.cluster.node.endpoint)
        try probe.expectNoMessage(for: .milliseconds(50))
    }
}
