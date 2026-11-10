// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: VersionVector

/// Version vectors are a mechanism to capture causality in distributed systems.
///
/// Often times the terms "version vector" and "vector clock" are used interchangeably. Indeed the two mechanisms share
/// similarities--both capture causality in distributed systems and their internal state are the same. However,
/// version vectors and vector clocks are not the same thing.
///
/// A vector clock establishes a partial order of events generated in a distributed system. The set of events might grow
/// indefinitely, so using integers for tracking makes sense.
///
/// In contrast, a version vector establishes a partial order of changes to data (i.e., we want to relate replica
/// states),
/// not the update events. Using integers is overly expressive and can be substituted by a limited set of symbols
/// instead.
///
/// For an in-depth discussion see [Version Vectors are not Vector
/// Clocks](https://haslab.wordpress.com/2011/07/08/version-vectors-are-not-vector-clocks/).
///
/// - SeeAlso: [Why Logical Clocks are Easy](https://queue.acm.org/detail.cfm?id=2917756)
/// - SeeAlso: [Version Vectors are not Vector
/// Clocks](https://haslab.wordpress.com/2011/07/08/version-vectors-are-not-vector-clocks/)
internal struct VersionVector: Equatable, Comparable, CustomStringConvertible, CustomPrettyStringConvertible, Codable {
    // should we disallow mixing ReplicaID types somehow?

    internal typealias Version = UInt64

    internal typealias ReplicaVersion = (replicaID: ReplicaID, version: Version)  // struct?

    internal enum CausalRelation {
        /// X < Y, meaning X → Y or X "happened before" Y
        case happenedBefore
        /// X > Y, meaning Y → X, or X "happened after" Y
        case happenedAfter
        /// X == Y
        case same
        /// X || Y, meaning neither X → Y nor Y → X; no causal relation between X and Y
        case concurrent
    }

    internal static let empty: VersionVector = .init()
    // Internal state is a dictionary of replicas and their corresponding version
    internal var state: [ReplicaID: Version] = [:]

    internal var isEmpty: Bool {
        self.state.isEmpty
    }

    internal var isNotEmpty: Bool {
        !self.isEmpty
    }
    /// Lists all replica ids that this version vector contains.
    internal var replicaIDs: Dictionary<ReplicaID, Version>.Keys {
        self.state.keys
    }

    internal var description: String {
        "\(self.state)"
    }
    /// Creates an 'empty' version vector.
    internal init() {
        self.state = [:]
    }

    internal init(_ versionVector: Self) {
        self.state.merge(versionVector.state) { _, new in new }
    }

    internal init(_ replicaVersion: ReplicaVersion) {
        self.init([replicaVersion])
    }

    internal init(_ version: Version, at replicaID: ReplicaID) {
        self.init([(replicaID, version)])
    }

    internal init(_ replicaVersions: [ReplicaVersion]) {
        for replicaVersion in replicaVersions {
            precondition(replicaVersion.version > 0, "Version must be greater than 0")
            self.state[replicaVersion.replicaID] = replicaVersion.version
        }
    }

    internal static func first(at replicaID: ReplicaID) -> Self {
        .init((replicaID, 1))
    }

    internal static func < (lhs: Self, rhs: Self) -> Bool {
        // If lhs is empty but rhs is not, then lhs can only be less than ("happened-before").
        // Return false if both lhs and rhs are empty since they are considered the same, not ordered.
        if lhs.isEmpty {
            return rhs.isNotEmpty
        }

        // If every entry in version vector X is less than or equal to the corresponding entry in
        // version vector Y, and at least one entry is strictly smaller, then X < Y.
        var hasAtLeastOneStrictlyLessThan: Bool = false
        for (replicaID, lVersion) in lhs.state {
            let rVersion: Version = rhs[replicaID]
            if lVersion > rVersion {
                return false
            }
            if lVersion < rVersion {
                hasAtLeastOneStrictlyLessThan = true
            }
        }
        return hasAtLeastOneStrictlyLessThan
    }

    internal static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state == rhs.state
    }

    /// Increment version at the given replica.
    ///
    /// - Parameter replicaID: The replica whose version is to be incremented.
    /// - Returns: The replica's version after the increment.
    @discardableResult
    internal mutating func increment(at replicaID: ReplicaID) -> Version {
        if let current = self.state[replicaID] {
            let nextVersion: Version = current + 1
            self.state[replicaID] = nextVersion
            return nextVersion
        }
        self.state[replicaID] = 1
        return 1
    }

    internal mutating func merge(other: Self) {
        // Take point-wise maximum
        self.state.merge(other.state, uniquingKeysWith: max)
    }

    /// Prune any trace of the passed in replica id.
    internal func pruneReplica(_ replicaID: ReplicaID) -> Self {
        var pruned: Self = self
        pruned.state.removeValue(forKey: replicaID)
        return pruned
    }

    /// Determine if this `VersionVector` contains a specific version at the given replica.
    ///
    /// - Parameter replicaID: The replica of interest
    /// - Parameter version: The version of interest
    /// - Returns: True if the replica's version in the `VersionVector` is greater than or equal to `version`. False
    /// otherwise.
    internal func contains(_ replicaID: ReplicaID, _ version: Version) -> Bool {
        self[replicaID] >= version
    }

    /// Compare this `VersionVector` with another and determine causality between the two.
    /// They can be ordered (i.e., one happened before or after another), same, or concurrent.
    ///
    /// - Parameter that: The `VersionVector` to compare this `VersionVector` to.
    /// - Returns: The causal relation between this and the given `VersionVector`.
    internal func compareTo(_ that: Self) -> CausalRelation {
        if self < that {
            return .happenedBefore
        }
        if self > that {
            return .happenedAfter
        }
        if self == that {
            return .same
        }
        return .concurrent
    }

    /// Obtain current version at the given replica. If the replica is unknown, the default version is 0.
    ///
    /// - Parameter replicaID: The replica whose version is being queried.
    /// - Returns: The replica's version or 0 if replica is unknown.
    internal subscript(replicaID: ReplicaID) -> Version {
        self.state[replicaID] ?? 0
    }
}
