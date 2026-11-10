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

import Distributed
import DistributedActorsTestKit
import Logging
import XCTest

@testable import DistributedCluster

internal distributed actor UnregisterOnMessage {
    internal typealias ActorSystem = ClusterSystem

    internal distributed func checkIn(with key: DistributedReception.Key<UnregisterOnMessage>) async {
        await actorSystem.receptionist.checkIn(self, with: key)
    }
}

internal distributed actor StringForwarder: CustomStringConvertible {
    internal typealias ActorSystem = ClusterSystem

    internal let probe: ActorTestProbe<String>

    nonisolated internal var description: String {
        "\(Self.self)(\(id))"
    }

    internal init(probe: ActorTestProbe<String>, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.probe = probe
    }

    //    distributed func forward(message: String) {
    internal distributed func forward(message: String) -> String {
        self.probe.tell("forwarded:\(message)")
        return "echo:\(message)"
    }
}

internal final class OpLogReceptionistClusteredTests: ClusteredActorSystemsXCTestCase {
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
            "/system/nodeDeathWatcher",

            "/dead/system/receptionist-ref",  // FIXME(distributed): it should simply be quiet
        ]
        settings.excludeGrep = [
            "timer"
        ]
    }

    override internal func configureActorSystem(settings: inout ClusterSystemSettings) {
        settings.receptionist.ackPullReplicationIntervalSlow = .milliseconds(300)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Sync

    internal func test_shouldReplicateRegistrations() async throws {
        let (first, second): (ClusterSystem, ClusterSystem) = await self.setUpPair()
        let testKit: ActorTestKit = self.testKit(first)
        try await self.joinNodes(node: first, with: second)

        let probe: ActorTestProbe<String> = testKit.makeTestProbe(expecting: String.self)

        // Create forwarder on 'first'
        let forwarder: StringForwarder = StringForwarder(probe: probe, actorSystem: first)

        // subscribe on `remote`
        let subscriberProbe: ActorTestProbe<StringForwarder> =
            testKit.makeTestProbe("subscriber", expecting: StringForwarder.self)
        let subscriptionTask: Task<Void, Never> = Task {
            for await discoveredForwarder in second.receptionist.listing(of: .stringForwarders) {
                subscriberProbe.tell(discoveredForwarder)
            }
        }
        defer {
            subscriptionTask.cancel()
        }

        // checkIn on `first`
        await first.receptionist.checkIn(forwarder, with: .stringForwarders)
        first.log.notice("Checked in: \(forwarder)")

        try await Task {
            let found: StringForwarder = try subscriberProbe.expectMessage()

            // we expect only one actor
            try subscriberProbe.expectNoMessage(for: .milliseconds(200))

            // check if we can interact with it
            let echo: String = try await found.forward(message: "test")
            echo.shouldEqual("echo:test")
            try probe.expectMessage("forwarded:test")
        }.value
    }

    internal func test_shouldSyncPeriodically() async throws {
        // Don't join the nodes just yet
        let (local, remote): (ClusterSystem, ClusterSystem) = await self.setUpPair { settings in
            settings.receptionist.ackPullReplicationIntervalSlow = .seconds(1)
        }

        let probe: ActorTestProbe<String> = self.testKit(local).makeTestProbe(expecting: String.self)
        let subscriberProbe: ActorTestProbe<StringForwarder> =
            self.testKit(local).makeTestProbe(expecting: StringForwarder.self)

        // Create on local
        let key: DistributedReception.Key = DistributedReception.Key(StringForwarder.self, id: "test")
        let forwarder: StringForwarder = StringForwarder(probe: probe, actorSystem: local)

        // Subscribe on remote
        let remoteSubscriberTask: Task<Void, Never> = Task {
            for await found in remote.receptionist.listing(of: key) {
                subscriberProbe.tell(found)
            }
        }
        defer { remoteSubscriberTask.cancel() }

        // Register on local
        await local.receptionist.checkIn(forwarder, with: key)

        // Join the nodes
        local.cluster.join(endpoint: remote.cluster.node.endpoint)
        try assertAssociated(local, withExactly: remote.settings.bindNode)

        // The remote node discovers the actor
        try await Task {
            let found: StringForwarder = try subscriberProbe.expectMessage()

            // we expect only one actor
            try subscriberProbe.expectNoMessage(for: .milliseconds(200))

            // check if we can interact with it
            let echo: String = try await found.forward(message: "test")
            echo.shouldEqual("echo:test")
            try probe.expectMessage("forwarded:test")
        }.value
    }
}

extension DistributedReception.Key {
    // The key is shared by a different type in this file.
    // swiftlint:disable:next strict_fileprivate
    fileprivate static var stringForwarders: DistributedReception.Key<StringForwarder> {
        "stringForwarders"
    }
}
