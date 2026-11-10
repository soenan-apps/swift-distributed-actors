// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import NIO
import XCTest

@testable import DistributedCluster

// Shared fixtures are used by test extensions in separate files.
// swiftlint:disable test_case_accessibility

/// Tests of just the datatype
internal final class MembershipGossipTests: XCTestCase {
    internal let nodeA: Cluster.Node = Cluster.Node(
        systemName: "firstA",
        host: "127.0.0.1",
        port: 7_111,
        nid: .random()
    )
    internal let nodeB: Cluster.Node = Cluster.Node(
        systemName: "secondB",
        host: "127.0.0.1",
        port: 7_222,
        nid: .random()
    )
    internal let nodeC: Cluster.Node = Cluster.Node(
        systemName: "thirdC",
        host: "127.0.0.1",
        port: 7_333,
        nid: .random()
    )
    internal let fourthNode: Cluster.Node = Cluster.Node(
        systemName: "fourthD",
        host: "127.0.0.1",
        port: 7_444,
        nid: .random()
    )
    internal lazy var allNodes: [Cluster.Node] = [
        self.nodeA, self.nodeB, self.nodeC, self.fourthNode,
    ]
}
// swiftlint:enable test_case_accessibility
