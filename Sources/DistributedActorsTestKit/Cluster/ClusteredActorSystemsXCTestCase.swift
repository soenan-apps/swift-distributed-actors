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

import DistributedActorsConcurrencyHelpers
import Foundation
import Logging
import SWIM
import XCTest

@testable import DistributedCluster

// This reusable base exposes configuration and helpers to importing test suites.
// swiftlint:disable test_case_accessibility

/// Convenience class for building multi-node (yet same-process) tests with many actor systems involved.
///
/// Systems started using `setUpNode` are automatically terminated upon test completion, and logs are automatically
/// captured and only printed when a test failure occurs.
open class ClusteredActorSystemsXCTestCase: XCTestCase {
    private static let inspectDetectActorLeaksEnv: Bool = {
        let configuredValue: String? = getenv("SACT_INSPECT_ACTOR_LEAKS").map { String(cString: $0).lowercased() }
        switch configuredValue {
        case "true", "y", "yes", "on", "1":
            return true

        default:
            return false
        }
    }()
    private let lock: DistributedActorsConcurrencyHelpers.Lock = DistributedActorsConcurrencyHelpers.Lock()
    private var nodesStorage: [ClusterSystem] = []
    private var testKitsStorage: [ActorTestKit] = []
    private var logCapturesStorage: [LogCapture] = []
    private var actorStatsBefore: InspectKit.ActorStats = .init()
    private var nextPortValue: Int = 9_001
    private var stuckTestDumpLogsTask: Task<Void, Error>?
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Actor leak detection
    /// Actor systems started by this test case, in creation order.
    public var nodes: [ClusterSystem] {
        self.nodesStorage
    }

    /// Test kits corresponding to the systems started by this test case.
    public var testKits: [ActorTestKit] {
        self.testKitsStorage
    }

    /// Captures corresponding to the systems started by this test case.
    public var logCaptures: [LogCapture] {
        self.logCapturesStorage
    }

    /// If true, will use ``InspectKit`` to detect actor leaks around tests run in this test suite.
    open var inspectDetectActorLeaks: Bool {
        Self.inspectDetectActorLeaksEnv
    }
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Log capture
    /// If `true` automatically captures all logs of all `setUpNode` started systems, and prints them if at least
    /// one test failure is encountered.
    /// If `false`, log capture is disabled and the systems will log messages normally.
    ///
    /// - Default: `true`
    open var captureLogs: Bool {
        true
    }

    /// Unconditionally dump logs if the test has been running longer than this duration.
    /// This is to help diagnose stuck tests.
    open var dumpLogsAfter: Duration {
        .seconds(60)
    }

    /// Enables logging all captured logs, even if the test passed successfully.
    /// - Default: `false`
    open var alwaysPrintCaptureLogs: Bool {
        false
    }

    open func configureLogCapture(settings _: inout LogCapture.Settings) {
        // just use defaults
    }

    /// Configuration to be applied to every actor system.
    ///
    /// Order in which configuration is changed:
    /// - default changes made by `ClusteredNodesTestBase`
    /// - changes made by `configureActorSystem`
    /// - changes made by `modifySettings`, which is a parameter of `setUpNode`
    open func configureActorSystem(settings _: inout ClusterSystemSettings) {
        // just use defaults
    }

    open func nextPort() -> Int {
        defer { self.nextPortValue += 1 }
        return self.nextPortValue
    }

    override open func setUp() async throws {
        if self.inspectDetectActorLeaks {
            self.actorStatsBefore = try InspectKit.actorStats()
        }
        self.stuckTestDumpLogsTask = Task.detached {
            try await Task.sleep(until: .now + self.dumpLogsAfter, clock: .continuous)
            guard !Task.isCancelled else {
                return
            }
            print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            print("!!!!!!!!!!               TEST SEEMS STUCK - DUMPING LOGS                   !!!!!!!!!!")
            print(
                "!!!!!!!!!!               PID: \(ProcessInfo.processInfo.processIdentifier) "
                    + "                             !!!!!!!!!!"
            )
            print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            self.printAllCapturedLogs()
        }
        try await super.setUp()
    }

    /// Set up a new node intended to be clustered.
    open func setUpNode(
        _ name: String,
        _ modifySettings: ((inout ClusterSystemSettings) -> Void)? = nil
    ) async -> ClusterSystem {
        let node: ClusterSystem = await ClusterSystem(name) { settings in
            settings.enabled = true
            settings.endpoint.port = self.nextPort()
            if self.captureLogs {
                var captureSettings: LogCapture.Settings = LogCapture.Settings()
                self.configureLogCapture(settings: &captureSettings)
                let capture: LogCapture = LogCapture(settings: captureSettings)
                settings.logging.baseLogger = capture.logger(label: name)
                settings.swim.logger = settings.logging.baseLogger
                self.lock.withLockVoid {
                    self.logCapturesStorage.append(capture)
                }
            }
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)
            // Make suspicion propagation faster
            settings.swim.lifeguard.maxLocalHealthMultiplier = 2
            settings.swim.lifeguard.suspicionTimeoutMin = .milliseconds(500)
            settings.swim.lifeguard.suspicionTimeoutMax = .seconds(1)
            self.configureActorSystem(settings: &settings)
            modifySettings?(&settings)
        }
        self.nodesStorage.append(node)
        self.testKitsStorage.append(.init(node))
        return node
    }

    /// Set up a new pair of nodes intended to be clustered
    public func setUpPair(
        _ modifySettings: ((inout ClusterSystemSettings) -> Void)? = nil
    ) async -> (ClusterSystem, ClusterSystem) {
        let first: ClusterSystem = await self.setUpNode("first", modifySettings)
        let second: ClusterSystem = await self.setUpNode("second", modifySettings)
        return (first, second)
    }

    override open func tearDown() async throws {
        self.stuckTestDumpLogsTask?.cancel()
        self.stuckTestDumpLogsTask = nil
        try await super.tearDown()
        let testsFailed: Bool = self.testRun?.totalFailureCount ?? 0 > 0
        if self.captureLogs, self.alwaysPrintCaptureLogs || testsFailed {
            self.printAllCapturedLogs()
        }
        for node in self.nodesStorage {
            node.log.warning("======================== TEST TEAR DOWN: SHUTDOWN ========================")
            try await node.shutdown().wait()
        }
        self.lock.withLockVoid {
            self.nodesStorage = []
            self.testKitsStorage = []
            self.logCapturesStorage = []
        }
        if self.inspectDetectActorLeaks {
            try await Task.sleep(until: .now + .seconds(2), clock: .continuous)
            let actorStatsAfter: InspectKit.ActorStats = try InspectKit.actorStats()
            if let error = self.actorStatsBefore.detectLeaks(latest: actorStatsAfter) {
                print(error.message)
            }
        }
    }

    /// Returns the kit belonging to a system started by this test case.
    public func testKit(_ system: ClusterSystem) -> ActorTestKit {
        guard
            let index = self.nodesStorage.firstIndex(where: { candidate in candidate.cluster.node == system.cluster.node
            })
        else {
            fatalError("Must only call with system that was spawned using `setUpNode()`, was: \(system)")
        }
        return self.testKitsStorage[index]
    }

    public func joinNodes(
        node: ClusterSystem,
        with other: ClusterSystem,
        ensureWithin: Duration? = nil,
        ensureMembers maybeExpectedStatus: Cluster.MemberStatus? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        node.cluster.join(endpoint: other.cluster.node.endpoint)
        try assertAssociated(node, withAtLeast: other.settings.bindNode)
        try assertAssociated(other, withAtLeast: node.settings.bindNode)
        if let expectedStatus = maybeExpectedStatus {
            if let specificTimeout = ensureWithin {
                try await self.ensureNodes(
                    expectedStatus,
                    nodes: other.cluster.node,
                    on: node,
                    within: specificTimeout,
                    file: file,
                    line: line
                )
            } else {
                try await self.ensureNodes(expectedStatus, nodes: other.cluster.node, on: node, file: file, line: line)
            }
        }
    }

    public func ensureNodes(
        _ status: Cluster.MemberStatus,
        nodes: Cluster.Node...,
        on system: ClusterSystem? = nil,
        within: Duration = .seconds(20),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await self.ensureNodes(status, nodes: nodes, on: system, within: within, file: file, line: line)
    }

    public func ensureNodes(
        atLeast status: Cluster.MemberStatus,
        nodes: Cluster.Node...,
        on system: ClusterSystem? = nil,
        within: Duration = .seconds(20),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await self.ensureNodes(atLeast: status, nodes: nodes, on: system, within: within, file: file, line: line)
    }

    public func ensureNodes(
        _ status: Cluster.MemberStatus,
        nodes: [Cluster.Node],
        on system: ClusterSystem? = nil,
        within: Duration = .seconds(20),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        guard let onSystem = system ?? self.nodesStorage.first(where: { !$0.isShuttingDown }) else {
            fatalError("Must at least have 1 system present to use [\(#function)]")
        }
        let testKit: ActorTestKit = self.testKit(onSystem)
        do {
            try await onSystem.cluster.waitFor(Set(nodes), status, within: within)
        } catch {
            throw testKit.error("\(error)", file: file, line: line)
        }
    }

    public func ensureNodes(
        atLeast status: Cluster.MemberStatus,
        nodes: [Cluster.Node],
        on system: ClusterSystem? = nil,
        within: Duration = .seconds(20),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        guard let onSystem = system ?? self.nodesStorage.first(where: { !$0.isShuttingDown }) else {
            fatalError("Must at least have 1 system present to use [\(#function)]")
        }
        let testKit: ActorTestKit = self.testKit(onSystem)
        do {
            // all members on onMember should have reached this status (e.g. up)
            try await onSystem.cluster.waitFor(Set(nodes), atLeast: status, within: within)
        } catch {
            throw testKit.error("\(error)", file: file, line: line)
        }
    }

    /// Returns the capture belonging to a system started by this test case.
    public func capturedLogs(of node: ClusterSystem) -> LogCapture {
        guard let index = self.nodesStorage.firstIndex(of: node) else {
            fatalError("No such node: [\(node)] in [\(self.nodesStorage)]!")
        }
        return self.lock.withLock {
            self.logCapturesStorage[index]
        }
    }
}
// swiftlint:enable test_case_accessibility
