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

import Distributed
import DistributedCluster

/// Timeouts and diagnostic behavior used while running a multi-node test.
public struct MultiNodeTestSettings {
    /// Filters log capture for an individual node.
    public struct MultiNodeLogCaptureSettings {
        /// Do not capture log messages which include the following strings.
        public var excludeGrep: Set<String> = []
    }

    /// Selects when logs from child nodes are printed.
    public enum DumpNodeLogSettings {
        /// Prints logs after every test.
        case always
        /// Prints logs only after a test failure.
        case onFailure
    }

    /// Total deadline for an 'exec' run of a test to complete running.
    /// After this deadline is exceeded the process is TERMINATED, harshly, without any error collecting or reporting.
    /// This is to prevent wedged nodes/tests lingering around.
    public var execRunHardTimeout: Duration

    /// Installs a logger that prints metadata as comments and includes source locations.
    public var installPrettyLogger: Bool = false

    /// How long to wait after the node process has been initialized,
    /// and before initializing the actor system on the child system.
    ///
    /// Useful when necessary to attach a debugger to a process before
    /// kicking off the actor system etc.
    public var waitBeforeBootstrap: Duration? = .seconds(10)

    /// How long the initial join of the nodes is allowed to take.
    public var initialJoinTimeout: Duration = .seconds(30)

    /// Capture filters applied to node logs.
    public var logCapture: MultiNodeLogCaptureSettings = .init()

    /// Configure when to dump logs from nodes
    public var dumpNodeLogs: DumpNodeLogSettings = .onFailure

    /// Wait time on entering a ``MultiNode/Checkpoint``.
    /// After exceeding the allocated wait time, all waiters are failed.
    ///
    /// I.e. "all nodes must reach this checkpoint within 30 seconds".
    public var checkPointWaitTime: Duration = .seconds(30)
    /// Creates the default timeout and diagnostic settings.
    public init() {
        self.execRunHardTimeout = .seconds(120)
    }
}
