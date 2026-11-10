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

/// A "dot" is a (replica, version) pair that represents a single, globally unique event.
///
/// `VersionDot` is in essence `VersionVector.ReplicaVersion` but since tuples cannot conform to protocols and `Version`
/// needs
/// to be `Hashable` we have to define a type.
internal struct VersionDot: Hashable, Comparable, CustomStringConvertible, Codable {
    internal typealias Version = UInt64

    internal let replicaID: ReplicaID
    internal let version: Version

    internal var description: String {
        "Dot(\(self.replicaID),\(self.version))"
    }

    internal init(_ replicaID: ReplicaID, _ version: Version) {
        self.replicaID = replicaID
        self.version = version
    }

    /// Lexical, NOT causal ordering of two dots.
    internal static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.replicaID == rhs.replicaID {
            return lhs.version < rhs.version
        }
        return lhs.replicaID < rhs.replicaID
    }
}
