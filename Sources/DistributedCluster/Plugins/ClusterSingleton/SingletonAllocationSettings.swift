// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

/// Selects the strategy that chooses a singleton host.
public struct SingletonAllocationSettings: Sendable {
    private enum AllocationStrategy {
        case byLeadership
        case custom(@Sendable (ClusterSingletonSettings, ClusterSystem) async -> any ClusterSingletonAllocationStrategy)
    }

    /// Hosts the singleton on the cluster leader.
    public static let byLeadership: SingletonAllocationSettings = .init(allocationStrategy: .byLeadership)

    private var allocationStrategy: AllocationStrategy

    /// Uses a caller-supplied allocation strategy.
    public static func custom<Strategy>(
        _ make: @Sendable @escaping (ClusterSingletonSettings, ClusterSystem) async -> Strategy
    ) -> Self where Strategy: ClusterSingletonAllocationStrategy {
        .init(allocationStrategy: .custom(make))
    }

    internal func makeAllocationStrategy(
        settings: ClusterSingletonSettings,
        actorSystem: ClusterSystem
    ) async -> ClusterSingletonAllocationStrategy {
        switch self.allocationStrategy {
        case .byLeadership:
            return ClusterSingletonAllocationByLeadership(settings: settings, actorSystem: actorSystem)

        case .custom(let make):
            return await make(settings, actorSystem)
        }
    }
}
