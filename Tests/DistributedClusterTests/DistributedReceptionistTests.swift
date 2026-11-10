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

internal distributed actor Forwarder {
    internal typealias ActorSystem = ClusterSystem

    internal let probe: ActorTestProbe<String>?
    internal let name: String

    internal init(probe: ActorTestProbe<String>?, name: String, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.probe = probe
        self.name = name
    }

    internal distributed func forward(message: String) {
        self.probe?.tell("\(self.id) \(self.name) forwarded: \(message)")
    }
}

internal distributed actor Boss: LifecycleWatch {
    internal typealias ActorSystem = ClusterSystem

    internal let probe: ActorTestProbe<String>?
    internal let name: String

    internal var workers: Set<ActorID> = []

    internal var listingTask: Task<Void, Never>?

    internal init(probe: ActorTestProbe<String>?, name: String, actorSystem: ActorSystem) {
        self.probe = probe
        self.actorSystem = actorSystem
        self.name = name
    }

    internal distributed func findWorkers() {
        guard self.listingTask == nil else {
            self.actorSystem.log.info("\(self.id) \(self.name) already looking for workers")
            return
        }

        self.listingTask = Task {
            for await worker in self.actorSystem.receptionist.listing(of: .workers) {
                self.workers.insert(watchTermination(of: worker).id)
                self.probe?.tell("\(self.id) \(self.name) found \(worker.id)")
            }
        }
    }

    internal func terminated(actor id: ActorID) {
        self.workers.remove(id)
    }

    internal distributed func done() {
        self.listingTask?.cancel()
        self.probe?.tell("\(self.name) done")
    }

    deinit {
        self.listingTask?.cancel()
        self.probe?.tell("\(self.name) deinit")
    }
}

internal distributed actor Worker: CustomStringConvertible {
    internal typealias ActorSystem = ClusterSystem

    internal let name: String

    nonisolated internal var description: String {
        "\(Self.self) \(self.id)"
    }

    internal init(name: String, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.name = name
    }

}

internal final class DistributedReceptionistTests: SingleClusterSystemXCTestCase {
    internal let receptionistBehavior: Behavior<Receptionist.Message> = OperationLogClusterReceptionist(
        settings: .default
    ).behavior

    internal func test_receptionist_mustHaveWellKnownID() {
        let opLogReceptionist: OpLogDistributedReceptionist = system.receptionist
        let id: ActorID = opLogReceptionist.id

        id.metadata.wellKnown.shouldEqual("receptionist")
        id.incarnation.shouldEqual(.wellKnown)
    }

    internal func test_receptionist_shouldRespondWithRegisteredRefsForKey() throws {
        try runAsyncAndBlock {
            let receptionist: OpLogDistributedReceptionist = system.receptionist
            let probe: ActorTestProbe<String> = self.testKit.makeTestProbe()

            let forwarderA: Forwarder = Forwarder(probe: probe, name: "A", actorSystem: system)
            let forwarderB: Forwarder = Forwarder(probe: probe, name: "B", actorSystem: system)

            await receptionist.checkIn(forwarderA, with: .forwarders)
            await receptionist.checkIn(forwarderB, with: .forwarders)

            let listing: Set<Forwarder> = await receptionist.lookup(.forwarders)
            listing.count.shouldEqual(2)
            for forwarder in listing {
                try await forwarder.forward(message: "test")
            }

            try probe.expectMessagesInAnyOrder(
                [
                    "\(forwarderA.id) A forwarded: test",
                    "\(forwarderB.id) B forwarded: test",
                ]
            )
        }
    }

}

extension DistributedReception.Key {
    internal static var forwarders: DistributedReception.Key<Forwarder> {
        "forwarder/*"
    }

    internal static var workers: DistributedReception.Key<Worker> {
        "worker/*"
    }

    /// A key that shall have NONE actors checked in
    internal static var unknown: DistributedReception.Key<Forwarder> {
        "unknown"
    }
}
