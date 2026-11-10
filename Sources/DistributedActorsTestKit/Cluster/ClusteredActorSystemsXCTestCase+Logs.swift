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

extension ClusteredActorSystemsXCTestCase {
    /// Prints a membership snapshot from the supplied system.
    public func pinfoMembership(_ system: ClusterSystem, file: StaticString = #fileID, line: UInt = #line) {
        let testKit: ActorTestKit = self.testKit(system)
        let probe: ActorTestProbe<Cluster.Membership> = testKit.makeTestProbe(expecting: Cluster.Membership.self)
        system.cluster.ref.tell(.query(.currentMembership(probe.ref)))
        let membership: Cluster.Membership
        do {
            membership = try probe.expectMessage()
        } catch {
            preconditionFailure("Unable to query membership: \(error)")
        }
        let info: String = "Membership on [\(reflecting: system.cluster.node)]: \(membership.prettyDescription)"
        probe.stop()
        pinfo(
            """
            \n
            MEMBERSHIP === -------------------------------------------------------------------------------------
            \(info)
            END OF MEMBERSHIP === ------------------------------------------------------------------------------
            """,
            file: file,
            line: line
        )
    }
}

extension ClusteredActorSystemsXCTestCase {
    /// Prints captured logs from the supplied system.
    public func printCapturedLogs(of node: ClusterSystem) {
        print("------------------------------------- \(node) ------------------------------------------------")
        self.capturedLogs(of: node).printLogs()
        print(String(repeating: "=", count: 120))
    }

    /// Prints captured logs from every started system.
    public func printAllCapturedLogs() {
        for node in self.nodes {
            self.printCapturedLogs(of: node)
        }
    }
}
