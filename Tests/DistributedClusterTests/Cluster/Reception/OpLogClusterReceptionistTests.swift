// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import Logging
import XCTest

@testable import DistributedCluster

internal final class OpLogClusterReceptionistTests: ClusteredActorSystemsXCTestCase {
    internal enum KillActorsMode {
        case sendStop
        case shutdownNode
    }

    internal let stopOnMessage: Behavior<String> = .receive { context, _ in
        context.log.warning("Stopping...")
        return .stop
    }

    override internal func configureLogCapture(settings: inout LogCapture.Settings) {
        settings.excludeActorPaths = [
            "/system/cluster/swim",
            "/system/cluster/gossip",
            "/system/replicator",
            "/system/cluster",
            "/system/clusterEvents",
            "/system/cluster/leadership",
        ]
        settings.excludeGrep = [
            "timer"
        ]
    }

    override internal func configureActorSystem(settings: inout ClusterSystemSettings) {
        settings.receptionist.ackPullReplicationIntervalSlow = .milliseconds(300)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Remove dead actors

    internal func shared_clusterReceptionist_shouldRemoveRemoteRefsStop(killActors: KillActorsMode) async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.receptionist.ackPullReplicationIntervalSlow = .seconds(1)
        }

        let registeredProbe: ActorTestProbe<Reception.Registered<ActorRef<String>>> =
            self.testKit(first).makeTestProbe(expecting: Reception.Registered<ActorRef<String>>.self)
        let remoteLookupProbe: ActorTestProbe<Reception.Listing<ActorRef<String>>> =
            self.testKit(second).makeTestProbe(expecting: Reception.Listing<ActorRef<String>>.self)

        let refA: ActorRef<String> = try first.spawn(.anonymous, self.stopOnMessage)
        let refB: ActorRef<String> = try first.spawn(.anonymous, self.stopOnMessage)

        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "test")

        first.actorRefReceptionist.register(refA, with: key, replyTo: registeredProbe.ref)
        _ = try registeredProbe.expectMessage()

        first.actorRefReceptionist.register(refB, with: key, replyTo: registeredProbe.ref)
        _ = try registeredProbe.expectMessage()

        second.actorRefReceptionist.subscribe(remoteLookupProbe.ref, to: key)
        _ = try remoteLookupProbe.expectMessage()

        first.cluster.join(endpoint: second.cluster.node.endpoint)
        try assertAssociated(first, withExactly: second.settings.bindNode)

        try remoteLookupProbe.eventuallyExpectListing(expected: [refA, refB], within: .seconds(3))

        switch killActors {
        case .sendStop:
            refA.tell("stop")
            refB.tell("stop")

        case .shutdownNode:
            try await first.shutdown().wait()
        }

        try remoteLookupProbe.eventuallyExpectListing(expected: [], within: .seconds(3))
    }
}
