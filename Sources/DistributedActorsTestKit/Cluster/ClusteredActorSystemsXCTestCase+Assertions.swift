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
    /// Waits until the system has the requested associations.
    public func assertAssociated(
        _ system: ClusterSystem,
        withAtLeast node: Cluster.Node,
        timeout: Duration? = nil,
        interval: Duration? = nil,
        verbose: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        try self.assertAssociated(
            system,
            withAtLeast: [node],
            timeout: timeout,
            interval: interval,
            verbose: verbose,
            file: file,
            line: line,
            column: column
        )
    }

    /// Waits until the system has the requested associations.
    public func assertAssociated(
        _ system: ClusterSystem,
        withExactly node: Cluster.Node,
        timeout: Duration? = nil,
        interval: Duration? = nil,
        verbose: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        try self.assertAssociated(
            system,
            withExactly: [node],
            timeout: timeout,
            interval: interval,
            verbose: verbose,
            file: file,
            line: line,
            column: column
        )
    }

    /// Query associated state of `system` for at-most `timeout` amount of time, and verify it contains exactly
    /// the passed in `nodes`.
    ///
    /// - Parameters:
    /// - withExactly: specific set of nodes that must exactly match the associated nodes on `system`; i.e. no
    /// extra associated nodes are allowed
    ///   - withAtLeast: sub-set of nodes that must be associated
    /// Waits until the system has the requested associations.
    public func assertAssociated(
        _ system: ClusterSystem,
        withExactly exactlyNodes: [Cluster.Node] = [],
        withAtLeast atLeastNodes: [Cluster.Node] = [],
        timeout: Duration? = nil,
        interval _: Duration? = nil,
        verbose: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let testKit: ActorTestKit = self.testKit(system)
        let probe: ActorTestProbe<Set<Cluster.Node>> = testKit.makeTestProbe(
            .prefixed(with: "probe-assertAssociated"),
            expecting: Set<Cluster.Node>.self,
            file: file,
            line: line
        )
        defer { probe.stop() }
        try testKit.eventually(within: timeout ?? .seconds(8), file: file, line: line, column: column) {
            system.cluster.ref.tell(.query(.associatedNodes(probe.ref)))
            let associatedNodes: Set<Cluster.Node> = try probe.expectMessage(file: file, line: line)
            if verbose {
                pprint("                   Self: \(String(reflecting: system.settings.bindNode))")
                pprint("       Associated nodes: \(associatedNodes.map { String(reflecting: $0) })")
                pprint("   Expected exact nodes: \(String(reflecting: exactlyNodes))")
                pprint("Expected at least nodes: \(String(reflecting: atLeastNodes))")
            }
            try self.checkAssociations(
                associatedNodes,
                on: system,
                exactly: exactlyNodes,
                atLeast: atLeastNodes
            )
        }
    }

    /// Asserts that the specified association remains absent.
    public func assertNotAssociated(
        system: ClusterSystem,
        node: Cluster.Node,
        timeout: Duration? = nil,
        interval _: Duration? = nil,
        verbose: Bool = false
    ) throws {
        let testKit: ActorTestKit = self.testKit(system)
        let probe: ActorTestProbe<Set<Cluster.Node>> = testKit.makeTestProbe(
            .prefixed(with: "assertNotAssociated-probe"),
            expecting: Set<Cluster.Node>.self
        )
        defer { probe.stop() }
        try testKit.assertHolds(for: timeout ?? .seconds(1)) {
            system.cluster.ref.tell(.query(.associatedNodes(probe.ref)))
            let associatedNodes: Set<Cluster.Node> = try probe.expectMessage()
            if verbose {
                pprint(
                    "                  Self: \(String(reflecting: system.settings.bindNode))",
                    function: #function,
                    file: #fileID,
                    line: #line
                )
                pprint(
                    "      Associated nodes: \(associatedNodes.map { String(reflecting: $0) })",
                    function: #function,
                    file: #fileID,
                    line: #line
                )
                pprint(
                    "     Not expected node: \(String(reflecting: node))",
                    function: #function,
                    file: #fileID,
                    line: #line
                )
            }
            if associatedNodes.contains(node) {
                throw TestError("[\(system)] unexpectedly associated with node: [\(node)]")
            }
        }
    }

    /// Asserts the given member node has the expected `status` within the duration.
    /// Waits until the member reaches the requested status.
    public func assertMemberStatus(
        on system: ClusterSystem,
        node: Cluster.Node,
        is expectedStatus: Cluster.MemberStatus,
        within: Duration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let testKit: ActorTestKit = self.testKit(system)
        do {
            _ = try await system.cluster.waitFor(node, expectedStatus, within: within)
        } catch let error as Cluster.MembershipError {
            switch error.underlying.error {
            case .notFound:
                throw testKit.error(
                    "Expected [\(system.cluster.node)] to know about [\(node)] "
                        + "member",
                    file: file,
                    line: line
                )

            case .statusRequirementNotMet(_, let foundMember):
                throw testKit.error(
                    """
                    Expected \(reflecting: foundMember.node) on \(reflecting: system.cluster.node) \
                    to be seen as: [\(expectedStatus)], but was [\(foundMember.status)]
                    """,
                    file: file,
                    line: line
                )

            default:
                throw testKit.error(error.description, file: file, line: line)
            }
        }
    }

    /// Waits until the member reaches the requested status.
    public func assertMemberStatus(
        on system: ClusterSystem,
        node: Cluster.Node,
        atLeast expectedAtLeastStatus: Cluster.MemberStatus,
        within: Duration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let testKit: ActorTestKit = self.testKit(system)
        do {
            _ = try await system.cluster.waitFor(node, atLeast: expectedAtLeastStatus, within: within)
        } catch let error as Cluster.MembershipError {
            switch error.underlying.error {
            case .notFound:
                throw testKit.error(
                    "Expected [\(system.cluster.node)] to know about [\(node)] "
                        + "member",
                    file: file,
                    line: line
                )

            case .atLeastStatusRequirementNotMet(_, let foundMember):
                throw testKit.error(
                    """
                    Expected \(reflecting: foundMember.node) on \(reflecting: system.cluster.node) \
                    to be seen as at-least: [\(expectedAtLeastStatus)], but was [\(foundMember.status)]
                    """,
                    file: file,
                    line: line
                )

            default:
                throw testKit.error(error.description, file: file, line: line)
            }
        }
    }

    /// Assert based on the event stream of ``Cluster/Event`` that the given `node` was downed or removed.
    public func assertMemberDown(_ eventStreamProbe: ActorTestProbe<Cluster.Event>, node: Cluster.Node) throws {
        let events: [Cluster.Event] = try eventStreamProbe.fishFor(Cluster.Event.self, within: .seconds(5)) { event in
            switch event {
            case .membershipChange(let change)
            where change.node == node && change.status.isAtLeast(.down):
                return .catchComplete(event)

            default:
                return .ignore
            }
        }
        guard events.first != nil else {
            guard let kit = self.testKits.first else {
                preconditionFailure("At least one test kit is required to assert member events")
            }
            throw kit.fail("Expected to capture cluster event about \(node) being down or removed, yet none captured!")
        }
    }

    /// Asserts the given node is the leader.
    ///
    /// An error is thrown but NOT failing the test; use in pair with `testKit.eventually` to achieve the expected
    /// behavior.
    public func assertLeaderNode(
        on system: ClusterSystem,
        is expectedNode: Cluster.Node?,
        file _: StaticString = #filePath,
        line _: UInt = #line
    ) throws {
        let testKit: ActorTestKit = self.testKit(system)
        let probe: ActorTestProbe<Cluster.Membership> = testKit.makeTestProbe(expecting: Cluster.Membership.self)
        defer {
            probe.stop()
        }
        system.cluster.ref.tell(.query(.currentMembership(probe.ref)))
        let membership: Cluster.Membership = try probe.expectMessage()
        let leaderNode: Cluster.Node? = membership.leader?.node
        if leaderNode != expectedNode {
            throw testKit.error(
                "Expected \(reflecting: expectedNode) to be leader node on "
                    + "\(reflecting: system.cluster.node) but was [\(reflecting: leaderNode)]"
            )
        }
    }

    private func checkAssociations(
        _ associatedNodes: Set<Cluster.Node>,
        on system: ClusterSystem,
        exactly exactlyNodes: [Cluster.Node],
        atLeast atLeastNodes: [Cluster.Node]
    ) throws {
        if !atLeastNodes.isEmpty {
            // atLeast set is a sub set of the right one
            let notYetAssociated: Set<Cluster.Node> = Set(atLeastNodes).subtracting(Set(associatedNodes))
            if !notYetAssociated.isEmpty {
                throw TestError(
                    """
                    [\(system)] still did not associate \(notYetAssociated). \
                    Associated nodes: \(reflecting: associatedNodes), expected nodes: \(reflecting: atLeastNodes).
                    """
                )
            }
        }
        if !exactlyNodes.isEmpty {
            var diff: Set<Cluster.Node> = Set(associatedNodes)
            diff.formSymmetricDifference(exactlyNodes)
            guard diff.isEmpty else {
                throw TestError(
                    """
                    [\(system)] did not associate the expected nodes: [\(exactlyNodes)].
                      Associated nodes: \(reflecting: associatedNodes), expected nodes: \(reflecting: exactlyNodes),
                      diff: \(reflecting: diff).
                    """
                )
            }
        }
    }
}
