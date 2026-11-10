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
import XCTest

@testable import DistributedCluster

internal final class BlockingReceptacleTests: XCTestCase {
    internal func test_blockingReceptacle_singleThreadedOfferWait() {
        let receptacle: BlockingReceptacle<String> = BlockingReceptacle()

        receptacle.offerOnce("hello")
        let res: String? = receptacle.wait(atMost: .milliseconds(10))
        res.shouldEqual("hello")
    }

    internal func test_blockingReceptacle_twoThreads() throws {
        let receptacle: BlockingReceptacle<String> = BlockingReceptacle()

        _ = try ClusterThread {
            receptacle.offerOnce("hello")
        }

        let res: String? = receptacle.wait(atMost: .milliseconds(200))
        res.shouldEqual("hello")
    }

    internal func test_blockingReceptacle_manyWaiters() throws {
        let receptacle: BlockingReceptacle<String> = BlockingReceptacle()

        _ = try ClusterThread {
            let res: String? = receptacle.wait(atMost: .milliseconds(200))
            res.shouldEqual("hello")
        }

        _ = try ClusterThread {
            let res: String? = receptacle.wait(atMost: .milliseconds(200))
            res.shouldEqual("hello")
        }

        _ = try ClusterThread {
            receptacle.offerOnce("hello")
        }

        let res: String? = receptacle.wait(atMost: .milliseconds(200))
        res.shouldEqual("hello")
    }
}
