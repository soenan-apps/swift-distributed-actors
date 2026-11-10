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

private enum LeadershipSelectionStorage {
    case disabled
    case lowestReachable(minNumberOfMembers: Int)
}

extension ClusterSystemSettings {
    /// Selects how the cluster elects a leader.
    public struct LeadershipSelectionSettings {
        /// Disables automatic election; applications may publish their own leadership-change decisions.
        public static let disabled: LeadershipSelectionSettings = .init(underlying: .disabled)

        private let underlying: LeadershipSelectionStorage

        /// Selects the lowest reachable node address once enough members are present.
        public static func lowestReachable(minNumberOfMembers: Int) -> Self {
            .init(underlying: .lowestReachable(minNumberOfMembers: minNumberOfMembers))
        }

        internal func make(_: ClusterSystemSettings) -> LeaderElection? {
            switch self.underlying {
            case .disabled:
                return nil

            case .lowestReachable(let memberCount):
                return Leadership.LowestReachableMember(minimumNrOfMembers: memberCount)
            }
        }
    }
}
