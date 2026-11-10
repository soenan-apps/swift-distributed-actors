// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Foundation
import Logging
import NIO
import XCTest

@testable import DistributedCluster

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Membership Testing DSL

extension Cluster.MembershipGossip {
    /// First line is Membership DSL, followed by lines of the SeenTable DSL
    internal static func parse(
        _ dsl: String,
        owner: Cluster.Node,
        nodes: [Cluster.Node],
        file: StaticString,
        line: UInt
    ) throws -> Cluster.MembershipGossip {
        let dslLines: [Substring] = dsl.split(separator: "\n")
        let membershipLine: Substring = try XCTUnwrap(dslLines.first, file: file, line: line)
        var gossip: Cluster.MembershipGossip = Cluster.MembershipGossip(ownerNode: owner)
        gossip.membership = try Cluster.Membership.parse(
            String(membershipLine),
            nodes: nodes,
            file: file,
            line: line
        )
        gossip.seen = try Self.SeenTable.parse(
            dslLines.dropFirst().joined(separator: "\n"),
            nodes: nodes,
            file: file,
            line: line
        )
        return gossip
    }
}

extension Cluster.MembershipGossip.SeenTable {
    /// Express seen tables using a DSL
    /// Syntax: each line: `<owner>: <node>@<version>*`
    internal static func parse(
        _ dslString: String,
        nodes: [Cluster.Node],
        file: StaticString,
        line: UInt
    ) throws -> Cluster.MembershipGossip.SeenTable {
        let rows: [Substring] = dslString.split(separator: "\n")
        func nodeById(id: Substring) throws -> Cluster.Node {
            try XCTUnwrap(
                nodes.first(where: { $0.systemName.contains(id) }),
                "Could not find node containing [\(id)] in \(nodes), for seen table: \(dslString)",
                file: file,
                line: line
            )
        }

        var table: Cluster.MembershipGossip.SeenTable = Cluster.MembershipGossip.SeenTable()
        for row in rows {
            let elements: [Substring] = row.split(separator: " ")
            let id: Substring = try XCTUnwrap(elements.first, file: file, line: line).dropLast(1)
            let ownerNode: Cluster.Node = try nodeById(id: id)
            var versionVector: VersionVector = VersionVector.empty
            for dslVersion in elements.dropFirst() {
                let parts: [Substring] = dslVersion.split { character in "@:".contains(character) }
                let atId: Substring = try XCTUnwrap(parts.first, file: file, line: line)
                let atNode: Cluster.Node = try nodeById(id: atId)
                let versionString: Substring = try XCTUnwrap(parts.dropFirst().first, file: file, line: line)
                let atVersion: UInt64 = try XCTUnwrap(UInt64(versionString), file: file, line: line)
                versionVector.state[.node(atNode)] = atVersion
            }
            table.underlying[ownerNode] = versionVector
        }
        return table
    }
}

extension VersionVector {
    internal static func parse(
        _ dslString: String,
        nodes: [Cluster.Node],
        file: StaticString,
        line: UInt
    ) throws -> VersionVector {
        func nodeById(id: Substring) throws -> Cluster.Node {
            try XCTUnwrap(
                nodes.first(where: { $0.systemName.contains(id) }),
                "Could not find node containing [\(id)] in \(nodes), for seen table: \(dslString)",
                file: file,
                line: line
            )
        }

        let replicaVersions: [VersionVector.ReplicaVersion] = try dslString.split(separator: " ").map { segment in
            let parts: [Substring] = segment.split { character in ":@".contains(character) }
            let nodeId: Substring = try XCTUnwrap(parts.first, file: file, line: line)
            let node: Cluster.Node = try nodeById(id: nodeId)
            let rawVersion: Substring = try XCTUnwrap(parts.dropFirst().first, file: file, line: line)
            let version: Self.Version = try XCTUnwrap(Self.Version(rawVersion), file: file, line: line)
            return (.node(node), version)
        }
        return VersionVector(replicaVersions)
    }
}

extension Cluster.Membership {
    /// Express membership as: `F.up S.down T.joining`.
    ///
    /// Syntax reference:
    ///
    /// ```
    /// <node identifier>[.:]<node status> || [leader:<node identifier>]
    /// ```
    internal static func parse(
        _ dslString: String,
        nodes: [Cluster.Node],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Cluster.Membership {
        func nodeById(id: Substring) throws -> Cluster.Node {
            try XCTUnwrap(
                nodes.first(where: { $0.systemName.contains(id) }),
                "Could not find node containing [\(id)] in \(nodes), for membership: \(dslString)",
                file: file,
                line: line
            )
        }

        var membership: Cluster.Membership = Self.empty
        for nodeDsl in dslString.split(separator: " ") {
            let elements: [Substring] = nodeDsl.split { character in ".:".contains(character) }
            let nodeId: Substring = try XCTUnwrap(elements.first, file: file, line: line)
            if nodeId == "[leader" {
                let rawLeaderId: Substring = try XCTUnwrap(elements.dropFirst().first, file: file, line: line)
                let leaderNode: Cluster.Node = try nodeById(id: rawLeaderId.dropLast(1))
                membership.leader = try XCTUnwrap(membership.member(leaderNode), file: file, line: line)
            } else {
                let node: Cluster.Node = try nodeById(id: nodeId)
                let rawStatus: Substring = try XCTUnwrap(elements.dropFirst().first, file: file, line: line)
                let status: Cluster.MemberStatus = try XCTUnwrap(
                    Cluster.MemberStatus.parse(String(rawStatus)),
                    file: file,
                    line: line
                )
                membership.membersByNode[node] = Cluster.Member(node: node, status: status)
            }
        }
        return membership
    }
}

extension Cluster.MemberStatus {
    /// Parses the persisted status spelling used by membership fixtures.
    internal static func parse(_ rawStatus: String) -> Cluster.MemberStatus? {
        Self(rawValue: rawStatus.trimmingCharacters(in: .symbols))
    }
}
