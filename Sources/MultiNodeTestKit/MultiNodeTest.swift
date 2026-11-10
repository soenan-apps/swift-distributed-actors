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
import OrderedCollections

/// A test descriptor and factories used to execute it on each named node.
public struct MultiNodeTest {
    /// Async test body specialized to a test suite node enumeration.
    public typealias RunTestFn<Nodes: MultiNodeNodes> = (Control<Nodes>) async throws -> Void

    /// Runner-assigned suite name.
    public var suiteNameStorage: String = ""
    /// Runner-assigned test name.
    public var testNameStorage: String = ""
    /// Names of all nodes participating in this test.
    public let nodeNames: OrderedSet<String>
    /// Expected crash output, when the test requires a crash.
    public let crashRegex: String?
    /// Executes the body using a control with the matching node type.
    public let runTest: (any MultiNodeTestControlProtocol) async throws -> Void
    /// Applies suite-specific actor system settings.
    public let configureActorSystem: (inout ClusterSystemSettings) -> Void
    /// Starts a system using suite-specific bootstrapping.
    public let startNode: (ClusterSystemSettings) async throws -> ClusterSystem
    /// Applies suite-specific runner settings.
    public let configureMultiNodeTest: (inout MultiNodeTestSettings) -> Void
    /// Builds a control for one named node.
    public let makeControl: (String) -> any MultiNodeTestControlProtocol

    /// Suite name reported by the runner.
    public var testSuiteName: String {
        self.suiteNameStorage
    }

    /// Test name reported by the runner.
    public var testName: String {
        self.testNameStorage
    }

    /// Qualified suite and test name.
    public var fullTestName: String {
        "\(self.testSuiteName).\(self.testName)"
    }

    /// Captures the suite factories and the selected test body.
    public init<TestSuite: MultiNodeTestSuite>(
        _: TestSuite.Type,
        _ runTest: @escaping RunTestFn<TestSuite.Nodes>
    ) {
        self.nodeNames = OrderedSet(TestSuite.Nodes.allCases.map(\.rawValue))
        self.crashRegex = nil
        self.runTest = { (anyControl: any MultiNodeTestControlProtocol) in
            guard let control = anyControl as? Control<TestSuite.Nodes> else {
                preconditionFailure("Control must match the test suite node type")
            }
            try await runTest(control)
        }

        self.configureActorSystem = TestSuite.configureActorSystem
        self.startNode = TestSuite.startNode
        self.configureMultiNodeTest = TestSuite.configureMultiNodeTest

        self.makeControl = { nodeName -> Control<TestSuite.Nodes> in
            Self.Control<TestSuite.Nodes>(nodeName: nodeName)
        }
    }
}
