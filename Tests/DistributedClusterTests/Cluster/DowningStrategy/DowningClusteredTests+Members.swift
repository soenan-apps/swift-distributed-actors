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

import DistributedActorsTestKit
import SWIM
import XCTest

@testable import DistributedCluster

extension DowningClusteredTests {
    internal func test_stopMember_by_leaveSelfNode_shouldPropagateToOtherNodes() async throws {
        try await self.shared_stoppingNode_shouldPropagateToOtherNodesAsDown(
            stopMethod: .leaveSelfNode,
            stopNode: .secondNonLeader
        ) { settings in
            settings.onDownAction = .gracefulShutdown(delay: .seconds(0))
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)

            settings.downingStrategy = self.downingStrategy
        }
    }

    internal func test_stopMember_by_downSelf_shouldPropagateToOtherNodes() async throws {
        try await self.shared_stoppingNode_shouldPropagateToOtherNodesAsDown(
            stopMethod: .downSelf,
            stopNode: .secondNonLeader
        ) { settings in
            settings.onDownAction = .gracefulShutdown(delay: .seconds(0))
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)

            settings.downingStrategy = self.downingStrategy
        }
    }

    internal func test_stopMember_by_downByMember_shouldPropagateToOtherNodes() async throws {
        try await self.shared_stoppingNode_shouldPropagateToOtherNodesAsDown(
            stopMethod: .downFromOtherMember,
            stopNode: .secondNonLeader
        ) { settings in
            settings.onDownAction = .gracefulShutdown(delay: .seconds(0))
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)

            settings.downingStrategy = self.downingStrategy
        }
    }

    internal func test_stopMember_by_shutdownSelf_shouldPropagateToOtherNodes() async throws {
        try await self.shared_stoppingNode_shouldPropagateToOtherNodesAsDown(
            stopMethod: .shutdownSelf,
            stopNode: .secondNonLeader
        ) { settings in
            settings.onDownAction = .gracefulShutdown(delay: .seconds(0))
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 2)

            settings.downingStrategy = self.downingStrategy
        }
    }
}
