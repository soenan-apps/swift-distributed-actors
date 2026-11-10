// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import ArgumentParser
import Dispatch
import DistributedCluster
import Logging
import MultiNodeTestKit
import NIOCore
import NIOPosix
import OrderedCollections

import struct Foundation.Date
import class Foundation.FileHandle
import class Foundation.ProcessInfo
import struct Foundation.URL

// ==== ----------------------------------------------------------------------------------------------------------------
extension MultiNodeTestKitRunnerBoot {
    /// Executes one node of a multi-node test in its dedicated process.
    internal func executeTest(
        multiNodeTest: MultiNodeTest, nodeName: String, allNodes endpoints: [MultiNode.Endpoint]
    ) async throws {
        var control: any MultiNodeTestControlProtocol = multiNodeTest.makeControl(nodeName)
        control.endpointsByName = self.convertAllNodes(allNodes: endpoints)
        guard let myNode = control.endpointsByName[nodeName] else {
            preconditionFailure("The prepared endpoint list must contain this node")
        }
        var settings: MultiNodeTestSettings = MultiNodeTestSettings()
        multiNodeTest.configureMultiNodeTest(&settings)
        if let waitBeforeBootstrap = settings.waitBeforeBootstrap {
            await prettyWait(
                seconds: waitBeforeBootstrap.seconds,
                hint: "before starting actor system (allow e.g. attaching lldb)"
            )
        }
        let actorSettings: ClusterSystemSettings = self.makeActorSettings(
            multiNodeTest, nodeName: nodeName, endpoint: myNode, settings: settings
        )
        let system: ClusterSystem = try await multiNodeTest.startNode(actorSettings)
        control.actorSystem = system
        self.installSignalHandler(system, test: multiNodeTest, nodeName: nodeName)
        let joinedNodes: Set<Cluster.Node> = try await self.joinOtherNodes(
            system, endpoints: control.endpoints(except: nodeName), settings: settings
        )
        control.conductorStorage = try await self.makeConductor(system, nodes: joinedNodes, settings: settings)
        do {
            print("TEST RUN ============================================".yellow)
            try await multiNodeTest.runTest(control)
            print("TEST DONE ============================================".green)
        } catch {
            print("TEST FAILED ============================================".red)
            throw error
        }
        try system.shutdown()
    }

    private func makeActorSettings(
        _ test: MultiNodeTest, nodeName: String, endpoint: Cluster.Endpoint, settings: MultiNodeTestSettings
    ) -> ClusterSystemSettings {
        var actorSettings: ClusterSystemSettings = ClusterSystemSettings(name: nodeName)
        actorSettings.bindHost = endpoint.host
        actorSettings.bindPort = endpoint.port
        if settings.installPrettyLogger {
            actorSettings.logging.baseLogger = Logger(label: nodeName) { label in
                PrettyMultiNodeLogHandler(nodeName: label, settings: settings.logCapture)
            }
        }
        actorSettings += ClusterSingletonPlugin()
        test.configureActorSystem(&actorSettings)
        return actorSettings
    }

    private func installSignalHandler(_ system: ClusterSystem, test: MultiNodeTest, nodeName: String) {
        let queue: DispatchQueue = DispatchQueue(
            label: "multi.node.\(test.testSuiteName).\(test.testName).\(nodeName).SignalHandlerQueue"
        )
        let source: any DispatchSourceSignal = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        source.setEventHandler {
            source.cancel()
            print(
                "\n[multi-node] received signal, initiating shutdown which should complete "
                    + "after the last request finished."
            )
            do {
                try system.shutdown()
            } catch {
                preconditionFailure("Signal-triggered shutdown failed: \(error)")
            }
        }
        signal(SIGINT, SIG_IGN)
        source.resume()
    }

    private func joinOtherNodes(
        _ system: ClusterSystem, endpoints: [Cluster.Endpoint], settings: MultiNodeTestSettings
    ) async throws -> Set<Cluster.Node> {
        print("CLUSTER JOIN ============================================".yellow)
        for other in endpoints {
            log("Prepare cluster: join [\(system.name)] with \(other)")
            system.cluster.join(endpoint: other)
        }
        var allNodes: Set<Cluster.Node> = [system.cluster.node]
        for other in endpoints {
            guard let joined = try await system.cluster.joined(
                endpoint: other, within: settings.initialJoinTimeout
            ) else {
                fatalError("[multi-node][\(system.name)] Failed to join \(other)!")
            }
            print("[multi-node] [\(system.cluster.node)] <= joined => \(joined)")
            allNodes.insert(joined.node)
        }
        return allNodes
    }

    private func makeConductor(
        _ system: ClusterSystem, nodes: Set<Cluster.Node>, settings: MultiNodeTestSettings
    ) async throws -> MultiNodeTestConductor {
        let singletonSettings: ClusterSingletonSettings = ClusterSingletonSettings()
        let conductorName: String = "$test-conductor"
        let conductor: MultiNodeTestConductor = try await system.singleton.host(
            name: conductorName, settings: singletonSettings
        ) { actorSystem in
            MultiNodeTestConductor(name: conductorName, allNodes: nodes, settings: settings, actorSystem: actorSystem)
        }
        let pong: String = try await conductor.ping(message: "init", from: "\(system.name)")
        log("Conductor ready, pong reply: \(pong)")
        return conductor
    }

    internal func convertAllNodes(allNodes: [MultiNode.Endpoint]) -> [String: Cluster.Endpoint] {
        let nodeList: [(String, Cluster.Endpoint)] = allNodes.map { endpoint in
            let node: Cluster.Endpoint = Cluster.Endpoint(
                systemName: endpoint.name, host: endpoint.sactHost, port: endpoint.sactPort
            )
            return (node.systemName, node)
        }
        return .init(uniqueKeysWithValues: nodeList)
    }
}
