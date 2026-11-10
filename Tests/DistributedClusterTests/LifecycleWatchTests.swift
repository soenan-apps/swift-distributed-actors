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
import DistributedActorsTestKit
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Romeo

internal distributed actor Romeo: LifecycleWatch, CustomStringConvertible {
    internal let probe: ActorTestProbe<String>
    internal lazy var log: Logger = Logger(actor: self)

    nonisolated internal var description: String {
        "\(Self.self)(\(id))"
    }

    internal init(probe: ActorTestProbe<String>, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.probe = probe
        probe.tell("Romeo init")
    }

    internal distributed func greet(_: String) {
        // nothing important here
    }

    internal func terminated(actor _: ActorID) {
        // ignore
    }

    deinit {
        //         probe.tell("Romeo deinit")
    }

}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Juliet

internal distributed actor Juliet: LifecycleWatch, CustomStringConvertible {
    internal let probe: ActorTestProbe<String>
    internal lazy var log: Logger = Logger(actor: self)

    nonisolated internal var description: String {
        "\(Self.self)(\(id))"
    }

    internal init(probe: ActorTestProbe<String>, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.probe = probe
        probe.tell("Juliet init")
    }

    internal distributed func meetWatch(_ romeo: Romeo, unwatch doUnwatch: Bool) {
        watchTermination(of: romeo)
        if doUnwatch {
            unwatchTermination(of: romeo)
        }
        self.log.info("Watched \(romeo)")
    }

    internal func terminated(actor id: ActorID) {
        self.log.info("Got terminated: \(id)")
        self.probe.tell("Received terminated: \(id)")
    }

}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Tests

internal final class LifecycleWatchTests: SingleClusterSystemXCTestCase, @unchecked Sendable {
    override internal func configureLogCapture(settings: inout LogCapture.Settings) {
        settings.excludeActorPaths = [
            "/system/cluster",
            "/system/gossip",
            "/system/cluster/gossip",
            "/system/receptionist",
            "/system/receptionist-ref",
            "/system/cluster/swim",
            "/system/clusterEvents",
        ]
    }

    internal func test_watch_shouldTriggerTerminatedWhenWatchedActorDeinits() async throws {
        let julietProbe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let romeoProbe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let juliet: Juliet = Juliet(probe: julietProbe, actorSystem: system)

        func meet() async throws {
            var romeo: Romeo? = Romeo(probe: romeoProbe, actorSystem: system)

            try await juliet.meetWatch(XCTUnwrap(romeo), unwatch: false)
            romeo = nil
        }
        try await meet()

        try julietProbe.expectMessage("Juliet init")
        try romeoProbe.expectMessage("Romeo init")
        try julietProbe.expectMessage(prefix: "Received terminated: /user/Romeo")
    }

    internal func test_watchThenUnwatch_shouldTriggerTerminatedWhenWatchedActorDeinits() async throws {
        let julietProbe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let romeoProbe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let juliet: Juliet = Juliet(probe: julietProbe, actorSystem: system)

        func meet() async throws {
            var romeo: Romeo? = Romeo(probe: romeoProbe, actorSystem: system)

            try await juliet.meetWatch(XCTUnwrap(romeo), unwatch: true)
            romeo = nil
        }
        try await meet()

        try julietProbe.expectMessage("Juliet init")
        try romeoProbe.expectMessage("Romeo init")
        try julietProbe.expectNoMessage(for: .milliseconds(300))
    }

    internal func test_watch_shouldTriggerTerminatedWhenNodeTerminates() async throws {
        try await shouldNotThrow {
            let julietProbe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
            let romeoProbe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)

            let (first, second): (ClusterSystem, ClusterSystem) = await self.setUpPair { settings in
                settings.enabled = true
            }
            try await joinNodes(node: first, with: second, ensureMembers: .operational)

            let juliet: Juliet = Juliet(probe: julietProbe, actorSystem: first)

            let romeo: Romeo = Romeo(probe: romeoProbe, actorSystem: second)
            let remoteRomeo: Romeo = try Romeo.resolve(id: romeo.id, using: first)
            try assertRemoteActor(remoteRomeo)

            try await juliet.meetWatch(remoteRomeo, unwatch: false)

            first.cluster.down(endpoint: second.cluster.node.endpoint)

            try julietProbe.expectMessage("Juliet init")
            try romeoProbe.expectMessage("Romeo init")
            try julietProbe.expectMessage(prefix: "Received terminated: /user/Romeo", within: .seconds(10))
        }
    }
}
