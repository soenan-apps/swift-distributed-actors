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

import DistributedCluster
import Logging
import OrderedCollections

extension MultiNodeTest {
    /// Per-node test operations and runtime state installed by the runner.
    public struct Control<Nodes: MultiNodeNodes>: MultiNodeTestControlProtocol {
        /// Simple name of the actor system node (e.g. "first").
        internal let nodeName: String
        public var actorSystem: ClusterSystem? {
            willSet {
                if let newValue {
                    precondition(newValue.name == self.nodeName, "Node name does not match set cluster system!")
                }
                if let systemLog = newValue?.log {
                    self.log = systemLog
                }
            }
        }

        /// Logger for this node, replaced with the system logger after startup.
        public var log: Logger = Logger(label: "multi-node")
        public var endpointsByName: [String: Cluster.Endpoint] = [:]
        public var conductorStorage: MultiNodeTestConductor?
        /// The "current" cluster system on which this code is executing.
        public var system: ClusterSystem {
            guard let runningSystem = self.actorSystem else {
                preconditionFailure("Actor system already released!")
            }
            return runningSystem
        }

        /// The "current" endpoint on which this code is executing.
        public var endpoint: Cluster.Endpoint {
            self.system.cluster.endpoint
        }

        /// The "current" node on which this code is executing.
        public var node: Cluster.Node {
            self.system.cluster.node
        }

        /// Conductor used to coordinate checkpoints across all participating nodes.
        public var conductor: MultiNodeTestConductor {
            guard let activeConductor = self.conductorStorage else {
                preconditionFailure("Conductor has not been installed")
            }
            return activeConductor
        }

        public var cluster: ClusterControl {
            self.system.cluster
        }

        public var allEndpoints: some Collection<Cluster.Endpoint> {
            self.endpointsByName.values
        }

        public init(nodeName: String) {
            self.nodeName = nodeName
        }

        public func endpoint(_ node: Nodes) -> Cluster.Endpoint {
            guard let targetEndpoint = endpointsByName[node.rawValue] else {
                fatalError("No such node: \(node) known to cluster control. Known nodes: \(self.endpointsByName.keys)")
            }
            return targetEndpoint
        }

        /// Returns `true` if the multi-node execution is currently running on the same
        /// `node` as is passed to this function. This allows for executing pieces of code,
        /// only on a specific node in the multi-node test execution.
        public func on(_ node: Nodes) -> Bool {
            node.rawValue == self.system.name
        }

        /// Runs the body only when this control represents the selected node.
        @discardableResult
        public func runOn<T: Sendable>(_ node: Nodes, body: (ClusterSystem) async throws -> T) async rethrows -> T? {
            if node.rawValue == self.system.name {
                if self.system.isTerminated {
                    fatalError("Attempted to runOn(\(node)) after terminating the actor system!")
                }
                return try await body(self.system)
            }
            return nil
        }

        /// Runs the body only when this control represents the selected node.
        @discardableResult
        public func runOn<T: Sendable>(_ node: Nodes, body: (ClusterSystem) throws -> T) rethrows -> T? {
            if node.rawValue == self.system.name {
                return try body(self.system)
            }
            return nil
        }

        /// Runs the body only when this control represents the selected node.
        @discardableResult
        public func runOn<T: Sendable>(_ node: Nodes, body: () async throws -> T) async rethrows -> T? {
            if node.rawValue == self.system.name {
                return try await body()
            }
            return nil
        }

        /// Runs the body only when this control represents the selected node.
        @discardableResult
        public func runOn<T: Sendable>(_ node: Nodes, body: () throws -> T) rethrows -> T? {
            if node.rawValue == self.system.name {
                return try body()
            }
            return nil
        }

        /// Enter a checkpoint with the given name.
        ///
        /// - Parameters:
        ///   - name:
        ///   - waitTime:
        ///   - file:
        ///   - line:
        /// - Throws:
        public func checkPoint(
            _ name: String,
            within waitTime: Duration? = nil,
            file: String = #fileID,
            line: UInt = #line
        ) async throws {
            let checkPoint: MultiNode.Checkpoint = MultiNode.Checkpoint(name: name, file: file, line: line)
            log.notice(
                """
                Checkpoint [\(name)], wait for all other nodes to arrive at the \
                same checkpoint ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                """
            )
            let startWait: ContinuousClock.Instant = .now
            do {
                try await self.conductor.enterCheckPoint(
                    node: self.system.name,
                    checkPoint: checkPoint,
                    waitTime: waitTime ?? .seconds(30)
                )
            } catch {
                log.notice(
                    """
                    Checkpoint [\(name)] timed out! \
                    xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
                    """
                )
                throw error
            }
            let endWait: ContinuousClock.Instant = .now
            log.notice(
                """
                Checkpoint [\(name)] passed, all nodes arrived within: \
                \(startWait - endWait) >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
                """
            )
        }

        /// Unavailable because the conductor does not support remote process termination.
        @available(*, unavailable, message: "Remote process termination is unsupported")
        public func kill(_: Nodes) {  // ignore-unacceptable-language
            fatalError("KILL NOT IMPLEMENTED")  // ignore-unacceptable-language
        }

        public subscript(_ nid: Nodes) -> Cluster.Endpoint {
            guard let targetEndpoint = self.endpointsByName[nid.rawValue] else {
                fatalError(
                    "No node present for [\(nid.rawValue)], available: \(self.endpointsByName) "
                        + "(on \(self.system))"
                )
            }
            return targetEndpoint
        }
    }
}
