// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift Distributed Actors project authors
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

internal final class BasicClusterSystemLifecycleTests: SingleClusterSystemXCTestCase, @unchecked Sendable {
    internal func test_system_shouldAssignIdentityAndReadyActor() throws {
        try runAsyncAndBlock {
            let first: ClusterSystem = await setUpNode("first")

            var stub: StubDistributedActor? = StubDistributedActor(actorSystem: first)
            _ = stub
            stub = nil

            let identity: CapturedLogMessage = try self.logCapture.awaitLogContaining(testKit, text: "Assign identity")
            let idString: String = try "\(XCTUnwrap(XCTUnwrap(identity.metadata)["actor/id"]))"
            let ready: CapturedLogMessage = try self.logCapture.awaitLogContaining(testKit, text: "Actor ready")
            try "\(XCTUnwrap(XCTUnwrap(ready.metadata)["actor/id"]))".shouldEqual(idString)
        }
    }
}
