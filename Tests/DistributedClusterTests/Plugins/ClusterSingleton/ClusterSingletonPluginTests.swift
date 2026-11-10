// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

internal final class ClusterSingletonPluginTests: SingleClusterSystemXCTestCase {
    internal func test_singletonPlugin_clusterDisabled() async throws {
        // Singleton should work just fine without clustering
        let test: ClusterSystem = await setUpNode("test") { settings in
            settings.enabled = false
            settings += ClusterSingletonPlugin()
        }

        let name: String = "the-one"

        // singleton.host
        let ref: TheSingleton = try await test.singleton.host(name: name) { actorSystem in
            TheSingleton(greeting: "Hello", actorSystem: actorSystem)
        }
        let reply: String = try await ref.greet(name: "Charlie")
        reply.shouldStartWith(prefix: "Hello Charlie!")

        // singleton.ref (proxy-only)
        let proxyRef: TheSingleton = try await test.singleton.proxy(TheSingleton.self, name: name)
        let proxyReply: String = try await proxyRef.greet(name: "Charlene")
        proxyReply.shouldStartWith(prefix: "Hello Charlene!")
    }

    internal func test_singleton_nestedSingleton() async throws {
        let system: ClusterSystem = await setUpNode("test") { settings in
            settings += ClusterSingletonPlugin()
        }

        let singleton: NestedActorSingleton = try await system.singleton.host(name: "test-singleton") { actorSystem in
            NestedActorSingleton(actorSystem: actorSystem)
        }

        let singletonID: ActorID = singleton.id
        let greeterID: ActorID = try await singleton.getGreeter().id

        pinfo("singleton proxy    id: \(singletonID)", file: #fileID, line: #line)
        pinfo("singleton actual   id: \(try await singleton.actualID())", file: #fileID, line: #line)
        pinfo("singleton(greeter) id: \(greeterID)", file: #fileID, line: #line)

        try await singleton.actualID().detailedDescription.shouldContain("test-singleton")
        // if this were true we would have crashed by a duplicate name already, but let's make sure:
        singletonID.shouldNotEqual(greeterID)
    }

    internal func test_plugin_hooks() async throws {
        let actorID: String = "actorHookID"
        let ready: XCTestExpectation = self.expectation(description: "actor-ready")
        let resigned: XCTestExpectation = self.expectation(description: "actor-resigned")
        resigned.assertForOverFulfill = false
        let started: XCTestExpectation = self.expectation(description: "plugin-started")
        let stopped: XCTestExpectation = self.expectation(description: "plugin-stopped")
        let plugin: TestActorLifecyclePlugin = TestActorLifecyclePlugin(
            onActorReady: { actor in
                guard let hookActor = actor as? LifecycleHookActor else {
                    return
                }
                Task {
                    let id: String? = try? await hookActor.getID()
                    XCTAssertEqual(id, actorID, "Expected \(actorID) as an ID")
                    ready.fulfill()
                }
            },
            onResignID: { _ in resigned.fulfill() },
            onStart: { _ in started.fulfill() },
            onStop: { _ in stopped.fulfill() }
        )
        let testNode: ClusterSystem = await setUpNode("test-hook") { settings in
            settings.enabled = false
            settings += plugin
        }

        do {
            let actor: LifecycleHookActor = LifecycleHookActor(actorSystem: testNode, customID: actorID)
            await fulfillment(of: [ready, started], timeout: 3.0)
            XCTAssertEqual(actor.id.node, testNode.cluster.node)
        }
        try testNode.shutdown()
        try await testNode.terminated
        await fulfillment(of: [resigned, stopped], timeout: 3.0)
    }

}
