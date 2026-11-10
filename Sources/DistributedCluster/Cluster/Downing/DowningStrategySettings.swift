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

/// Selects whether and how unreachable members are automatically marked down.
public struct DowningStrategySettings {
    private enum Storage {
        case disabled
        case timeout(TimeoutBasedDowningStrategySettings)
    }

    /// Disables automatic downing decisions.
    public static let disabled: DowningStrategySettings = .init(.disabled)

    private let underlying: Storage

    private init(_ underlying: Storage) {
        self.underlying = underlying
    }

    /// Marks unreachable members down after the configured timeout.
    public static func timeout(_ settings: TimeoutBasedDowningStrategySettings) -> Self {
        .init(.timeout(settings))
    }

    internal func make(_ clusterSystemSettings: ClusterSystemSettings) -> DowningStrategy? {
        switch self.underlying {
        case .disabled:
            return nil

        case .timeout(let settings):
            return TimeoutBasedDowningStrategy(settings, selfNode: clusterSystemSettings.bindNode)
        }
    }
}
