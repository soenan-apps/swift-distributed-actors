// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

/// Selects the current cluster leader as the singleton host.
public final class ClusterSingletonAllocationByLeadership: ClusterSingletonAllocationStrategy {
    private var allocatedNode: Cluster.Node?

    public var node: Cluster.Node? { self.allocatedNode }

    public init(settings _: ClusterSingletonSettings, actorSystem _: ClusterSystem) {
        self.allocatedNode = nil
    }

    public func onClusterEvent(_ clusterEvent: Cluster.Event) -> Cluster.Node? {
        switch clusterEvent {
        case .leadershipChange(let change):
            self.allocatedNode = change.newLeader?.node

        case .snapshot(let membership):
            self.allocatedNode = membership.leader?.node

        default:
            break
        }
        return self.allocatedNode
    }
}
