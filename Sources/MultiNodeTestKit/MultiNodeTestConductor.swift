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

public struct MultiNodeCheckPointError: Error, Codable {
    internal let nodeName: String
    internal let message: String
}

/// Namespace for multi-node coordination values.
public enum MultiNode {}

public distributed actor MultiNodeTestConductor: ClusterSingleton, CustomStringConvertible {
    public typealias ActorSystem = ClusterSystem
    internal typealias NodeName = String

    internal let name: NodeName
    internal var allNodes: Set<Cluster.Node>
    internal lazy var log: Logger = Logger(actor: self)
    internal let settings: MultiNodeTestSettings
    // === Checkpoints
    internal var activeCheckPoint: MultiNode.Checkpoint?
    internal var nodesAtCheckPoint: [String: CheckedContinuation<MultiNode.Checkpoint, Error>]
    private var clusterEventsTask: Task<Void, Never>?
    nonisolated public var description: String {
        "\(Self.self)(\(self.id))"
    }

    internal var checkpointMissingNodes: Set<String> {
        var missing: Set<String> = Set(self.allNodes.map(\.endpoint.systemName))
        for node in self.nodesAtCheckPoint.keys {
            missing.remove(node)
        }
        return missing
    }

    public init(name: String, allNodes: Set<Cluster.Node>, settings: MultiNodeTestSettings, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.settings = settings
        self.allNodes = allNodes
        self.name = name
        self.activeCheckPoint = nil
        self.nodesAtCheckPoint = [:]
    }

    /// Used to check if the conductor is responsive.
    public distributed func ping(message: String, from node: String) -> String {
        self.actorSystem.log.info("Conductor received ping: \(message) from \(node) (node.length: \(node.count))")
        return "pong:\(message) (conductor node: \(self.actorSystem.cluster.node))"
    }

    /// Waits for every participant to enter the checkpoint, using the supplied remote-call timeout.
    nonisolated public func enterCheckPoint(
        node: String,
        checkPoint: MultiNode.Checkpoint,
        waitTime: Duration
    ) async throws {
        try await RemoteCall.with(timeout: waitTime) {
            try await self.enterCheckpointRemotely(node: node, checkPoint: checkPoint)
        }
    }

    /// Reentrant; all nodes will enter the checkpoint and eventually be resumed once all have arrived.
    internal distributed func enterCheckpointRemotely(
        node: String,
        checkPoint: MultiNode.Checkpoint
    ) async throws {
        self.actorSystem.log.warning("Conductor received `enterCheckPoint` FROM \(node) INNER RECEIVED")
        self.log.notice("[multi-node][checkpoint:\(checkPoint.name)] Node [\(node)] entering checkpoint...")
        self.ensureClusterEventsListening()
        if self.activeCheckPoint == nil {
            // We are the first node to enter this checkpoint so lets activate it.
            return try await self.activateCheckPoint(node, checkPoint: checkPoint)
        }
        if self.activeCheckPoint == checkPoint {
            // We could be entering an existing checkpoint
            return try await self.enterActiveCheckPoint(node, checkPoint: checkPoint)
        }
        if let active = self.activeCheckPoint {
            try self.enterIllegalCheckpoint(node, active: active, entered: checkPoint)
        }
    }

    internal func enterActiveCheckPoint(_ node: String, checkPoint: MultiNode.Checkpoint) async throws {
        guard self.nodesAtCheckPoint[node] == nil else {
            throw MultiNodeCheckPointError(
                nodeName: node,
                message: "[multi-node][checkpoint:\(checkPoint.name)] Node [\(node)] entered "
                    + "checkpoint [\(checkPoint)] more than once!"
            )
        }
        let remainingNodes: Int = self.allNodes.count - 1 - self.nodesAtCheckPoint.count
        self.log.notice(
            """
            [multi-node][checkpoint:\(checkPoint.name) @ \
            \(self.nodesAtCheckPoint.count + 1)/\(self.allNodes.count)] \(node) \
            entered checkpoint [\(checkPoint)]... Waiting for \(remainingNodes) remaining nodes.
            """,
            metadata: [
                "multiNode/checkpoint": "\(checkPoint.name)",
                "multiNode/checkpoint/missing": .array(
                    self.checkpointMissingNodes.map { .string($0) }
                ),
            ]
        )
        // last node arriving at the checkpoint, resume them all!
        if remainingNodes == 0 {
            print(
                "[multi-node] [checkpoint:\(checkPoint.name)] All [\(self.allNodes.count)] "
                    + "nodes entered checkpoint! Release: \(checkPoint.name) at \(checkPoint.file):\(checkPoint.line)"
            )
            for waitingAtCheckpoint in self.nodesAtCheckPoint.values {
                waitingAtCheckpoint.resume(returning: checkPoint)
            }
            self.clearCheckPoint()
            return
        }
        // Kick off a timeout task
        let checkpointTimeoutTask: Task<Void, Never> = self.makeCheckpointTimeoutTask(node, checkPoint: checkPoint)
        _ = try await withCheckedThrowingContinuation { (resume: CheckedContinuation<MultiNode.Checkpoint, Error>) in
            checkpointTimeoutTask.cancel()
            self.setContinuation(node: node, continuation: resume)
        }
    }

    internal func activateCheckPoint(_ node: String, checkPoint: MultiNode.Checkpoint) async throws {
        guard self.activeCheckPoint == nil else {
            throw MultiNodeCheckPointError(
                nodeName: node,
                message: "Checkpoint already active, yet tried to activate first: \(checkPoint)"
            )
        }
        self.activeCheckPoint = checkPoint
        try await self.enterActiveCheckPoint(node, checkPoint: checkPoint)
    }

    internal func enterIllegalCheckpoint(
        _ node: String,
        active activeCheckPoint: MultiNode.Checkpoint,
        entered enteredCheckPoint: MultiNode.Checkpoint
    ) throws {
        throw MultiNodeCheckPointError(
            nodeName: node,
            message: "Attempted to enter \(enteredCheckPoint), but the current active "
                + "checkpoint was: \(activeCheckPoint)"
        )
    }

    internal func checkpointNodeBecameDown(_ change: Cluster.MembershipChange) {
        let nodeName: String = change.node.endpoint.systemName
        guard let checkpoint = self.activeCheckPoint else {
            return
        }
        let error: MultiNodeCheckPointError = MultiNodeCheckPointError(
            nodeName: nodeName,
            message: "Checkpoint [\(checkpoint.name)] failed, node [\(nodeName)] became "
                + "[\(change.status)] and therefore unable to reach the checkpoint!"
        )
        for (waitingNodeName, continuation) in self.nodesAtCheckPoint {
            self.log.warning(
                """
                Checkpoint [\(checkpoint.name)] failing. Node \(nodeName) became \
                at least [.down]. Failing waiting node [\(waitingNodeName)]
                """,
                metadata: [
                    "multiNode/checkpoint/error": "\(error)"
                ]
            )
            continuation.resume(throwing: error)
        }
        self.clearCheckPoint()
    }

    private func clearCheckPoint() {
        self.activeCheckPoint = nil
        self.nodesAtCheckPoint = [:]
    }

    internal func ensureClusterEventsListening() {
        guard self.clusterEventsTask == nil else {
            return
        }
        self.clusterEventsTask = Task {
            for await event in self.actorSystem.cluster.events {
                self.onClusterEvent(event)
            }
        }
    }

    internal func onClusterEvent(_ event: Cluster.Event) {
        switch event {
        case .membershipChange(let change):
            if change.status.isAtLeast(.down) {
                // Nodes downed while waiting cannot reach the checkpoint.
                if self.nodesAtCheckPoint.contains(where: { $0.key == change.node.endpoint.systemName }) {
                    self.checkpointNodeBecameDown(change)
                }
                self.allNodes.remove(change.member.node)
            }

        default:
            return
        }
    }

    internal func setContinuation(node: String, continuation: CheckedContinuation<MultiNode.Checkpoint, Error>) {
        self.nodesAtCheckPoint[node] = continuation
    }

    private func timeoutCheckpoint(_ node: String, checkPoint: MultiNode.Checkpoint) {
        // make sure it's the same checkpoint active still
        guard checkPoint == self.activeCheckPoint else {
            return
        }
        let missingNodes: Int = self.allNodes.count - 1 - self.nodesAtCheckPoint.count
        guard missingNodes > 0 else {
            return
        }
        guard let continuation = self.nodesAtCheckPoint.removeValue(forKey: node) else {
            return
        }
        let checkPointError: MultiNodeCheckPointError =
            MultiNodeCheckPointError(
                nodeName: node,
                message: "Checkpoint failed, members arrived: \(self.nodesAtCheckPoint) but "
                    + "missing [\(missingNodes)] nodes!"
            )
        self.log.warning(
            "Checkpoint failed, informing node [\(node)]",
            metadata: [
                "checkPoint/node": "\(node)",
                "checkPoint/error": "\(checkPointError)",
            ]
        )
        continuation.resume(throwing: checkPointError)
    }

    private func makeCheckpointTimeoutTask(
        _ node: String,
        checkPoint: MultiNode.Checkpoint
    ) -> Task<Void, Never> {
        Task {
            do {
                try await Task.sleep(until: .now + self.settings.checkPointWaitTime, clock: .continuous)
                self.timeoutCheckpoint(node, checkPoint: checkPoint)
            } catch {
                // cancelled -> the checkpoint was resumed successfully
                return
            }
        }
    }
    deinit {
        guard __isLocalActor(self) else {  // workaround for old toolchains
            return
        }
        self.clusterEventsTask?.cancel()
    }
}
