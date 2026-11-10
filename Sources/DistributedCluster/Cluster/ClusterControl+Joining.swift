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

extension ClusterControl {
    /// Wait, within the given duration, until this actor system has joined the cluster and become
    /// ``Cluster/MemberStatus/operational``.
    ///
    /// - Parameters
    ///   - node: The node to be joined by this system.
    ///   - within: Duration to wait for.
    ///
    /// - Returns `Cluster.Member` for the joined node.
    @discardableResult
    public func joined(within: Duration) async throws -> Cluster.Member {
        // waiting to be "joined" means having passed the "joining" member status
        let myself: Cluster.Member = await self.member
        if myself.status > .joining {
            return myself
        }

        return try await self.waitFor(self.node, .operational, within: within)
    }

    /// Wait, within the given duration, until the passed in node has joined the cluster and become
    /// ``Cluster/MemberStatus/operational``.
    ///
    /// - Parameters
    ///   - node: The node to be joined by this system.
    ///   - within: Duration to wait for.
    ///
    /// - Returns `Cluster.Member` for the joined node.
    @discardableResult
    public func joined(node: Cluster.Node, within: Duration) async throws -> Cluster.Member {
        // waiting to be "joined" means having passed the "joining" member status
        if let matchedMember = await self.membershipSnapshot.member(node),
            matchedMember.status > .joining {
            return matchedMember
        }

        self.join(node: node)  // kick off the joining process in case we're not trying to already
        return try await self.waitFor(node, .operational, within: within)
    }

    /// Wait, within the given duration, until the passed in endpoint has joined the cluster and become
    /// ``Cluster/MemberStatus/operational``.
    ///
    /// - Parameters
    ///   - endpoint: The endpoint to be joined by this system.
    ///   - within: Duration to wait for.
    ///
    /// - Returns `Cluster.Member` for the joined node.
    @discardableResult
    public func joined(endpoint: Cluster.Endpoint, within: Duration) async throws -> Cluster.Member? {
        // waiting to be "joined" means having passed the "joining" member status
        if let matchedMember = await self.membershipSnapshot.anyMember(forEndpoint: endpoint),
            matchedMember.status > .joining {
            return matchedMember
        }

        self.join(endpoint: endpoint)  // kick off the joining process in case we're not trying to already
        return try await self.waitFor(endpoint, .operational, within: within)
    }

    /// Wait, within the given duration, for this actor system to be a member of all the nodes' respective cluster and
    /// have the specified status.
    ///
    /// - Parameters
    ///   - nodes: The nodes to be joined by this system.
    ///   - status: The expected member status.
    ///   - within: Duration to wait for.
    public func waitFor(
        _ nodes: some Collection<Cluster.Node>,
        _ status: Cluster.MemberStatus,
        within: Duration
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for waitingNode in nodes {
                group.addTask {
                    try await waitFor(waitingNode, status, within: within)
                }
            }
            // loop explicitly to propagate any error that might have been thrown
            for try await _ in group {
                // Iteration propagates a failed child result before leaving the task group.
            }
        }
    }

    /// Wait, within the given duration, for this actor system to be a member of all the nodes' respective cluster and
    /// have **at least** the specified status.
    ///
    /// - Parameters
    ///   - nodes: The nodes to be joined by this system.
    ///   - atLeastStatus: The minimum expected member status.
    ///   - within: Duration to wait for.
    public func waitFor(
        _ nodes: some Collection<Cluster.Node>,
        atLeast atLeastStatus: Cluster.MemberStatus,
        within: Duration
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for waitingNode in nodes {
                group.addTask {
                    _ = try await waitFor(waitingNode, atLeast: atLeastStatus, within: within)
                }
            }
            // loop explicitly to propagate any error that might have been thrown
            for try await _ in group {
                // Iteration propagates a failed child result before leaving the task group.
            }
        }
    }
}
