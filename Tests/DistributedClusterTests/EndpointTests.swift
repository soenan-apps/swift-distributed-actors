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
import Foundation
import XCTest

@testable import DistributedCluster

internal final class EndpointTests: XCTestCase {
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Endpoint

    internal func test_nodes_equal_whenHostPortMatch() {
        let alpha: Cluster.Endpoint = Cluster.Endpoint(systemName: "SystemNameAlpha", host: "111.111.11.1", port: 1_111)
        let beta: Cluster.Endpoint = Cluster.Endpoint(systemName: "SystemNameBeta", host: "111.111.11.1", port: 1_111)

        // system names are only for human readability / debugging, not equality
        alpha.shouldEqual(beta)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Cluster.Node

    internal func test_node_shouldRenderProperly() {
        let endpoint: Cluster.Endpoint = Cluster.Endpoint(systemName: "SystemName", host: "188.121.122.3", port: 1_111)
        let node: Cluster.Node = Cluster.Node(endpoint: endpoint, nid: Cluster.Node.Identifier(2_222))

        "\(node)".shouldEqual("sact://SystemName@188.121.122.3:1111")
        "\(String(reflecting: node))".shouldEqual("sact://SystemName:2222@188.121.122.3:1111")
    }

    internal func test_node_comparison_equal() {
        let two: Cluster.Node = Cluster.Node(
            endpoint: Cluster.Endpoint(
                systemName: "SystemName",
                host: "188.121.122.3",
                port: 1_111
            ),
            nid: Cluster.Node.Identifier(2_222)
        )
        let anotherTwo: Cluster.Node = two

        two.shouldEqual(anotherTwo)
        two.shouldBeLessThanOrEqual(anotherTwo)
    }

    internal func test_node_comparison_lessThan() {
        let two: Cluster.Node = Cluster.Node(
            endpoint: Cluster.Endpoint(
                systemName: "SystemName",
                host: "188.121.122.3",
                port: 1_111
            ),
            nid: Cluster.Node.Identifier(2_222)
        )
        let three: Cluster.Node = Cluster.Node(
            endpoint: Cluster.Endpoint(
                systemName: "SystemName",
                host: "188.121.122.3",
                port: 1_111
            ),
            nid: Cluster.Node.Identifier(3_333)
        )

        two.shouldBeLessThan(three)
    }
}
