// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

// Shared fixtures are used by test extensions in separate files.
// swiftlint:disable test_case_accessibility

internal final class VersionVectorTests: XCTestCase {
    private let node: Cluster.Node = Cluster.Node(systemName: "Test", host: "127.0.0.1", port: 7_337, nid: .random())
    internal lazy var replicaA: Result<ReplicaID, any Error> = Result {
        try .actorID(ActorPath.userRoot.appending("A").makeLocalID(on: node, incarnation: .random()))
    }
    internal lazy var replicaB: Result<ReplicaID, any Error> = Result {
        try .actorID(ActorPath.userRoot.appending("B").makeLocalID(on: node, incarnation: .random()))
    }
    internal lazy var replicaC: Result<ReplicaID, any Error> = Result {
        try .actorID(ActorPath.userRoot.appending("C").makeLocalID(on: node, incarnation: .random()))
    }

    // MARK: VersionVector tests

    internal func test_VersionVector_init_default_canModify() throws {
        var versionVector: VersionVector = VersionVector()
        versionVector.isEmpty.shouldBeTrue()

        // Add "A"
        versionVector.increment(at: try self.replicaA.get()).shouldEqual(1)
        versionVector[try self.replicaA.get()].shouldEqual(1)  // New replica gets added with version 1

        // Increment "A"
        versionVector.increment(at: try self.replicaA.get()).shouldEqual(2)
        versionVector[try self.replicaA.get()].shouldEqual(2)  // 1 + 1

        // Add "B"
        versionVector.increment(at: try self.replicaB.get()).shouldEqual(1)
        versionVector[try self.replicaA.get()].shouldEqual(2)  // No change
        versionVector[try self.replicaB.get()].shouldEqual(1)  // New replica gets added with version 1
    }

    internal func test_VersionVector_init_fromVersionVector_canModify() throws {
        let sourceVV: VersionVector = VersionVector([
            (try self.replicaA.get(), VersionVector.Version(1)),
            (try self.replicaB.get(), VersionVector.Version(2)),
        ])
        var versionVector: VersionVector = VersionVector(sourceVV)
        versionVector.isNotEmpty.shouldBeTrue()

        versionVector[try self.replicaA.get()].shouldEqual(1)
        versionVector[try self.replicaB.get()].shouldEqual(2)
        versionVector[try self.replicaC.get()].shouldEqual(0)  // default

        // Increment "B"
        versionVector.increment(at: try self.replicaB.get()).shouldEqual(3)
        versionVector[try self.replicaA.get()].shouldEqual(1)  // No change
        versionVector[try self.replicaB.get()].shouldEqual(3)  // 2 + 1

        // Add "C"
        versionVector.increment(at: try self.replicaC.get()).shouldEqual(1)
        versionVector[try self.replicaC.get()].shouldEqual(1)  // New replica gets added with version 1
    }

    internal func test_VersionVector_init_fromArrayOfReplicaVersionTuples_canModify() throws {
        var versionVector: VersionVector = VersionVector([
            (try self.replicaA.get(), VersionVector.Version(1)),
            (try self.replicaB.get(), VersionVector.Version(2)),
        ])
        versionVector.isNotEmpty.shouldBeTrue()

        versionVector[try self.replicaA.get()].shouldEqual(1)
        versionVector[try self.replicaB.get()].shouldEqual(2)
        versionVector[try self.replicaC.get()].shouldEqual(0)  // default

        // Increment "B"
        versionVector.increment(at: try self.replicaB.get()).shouldEqual(3)
        versionVector[try self.replicaA.get()].shouldEqual(1)  // No change
        versionVector[try self.replicaB.get()].shouldEqual(3)  // 2 + 1

        // Add "C"
        versionVector.increment(at: try self.replicaC.get()).shouldEqual(1)
        versionVector[try self.replicaC.get()].shouldEqual(1)  // New replica gets added with version 1
    }

    internal func test_VersionVector_merge_shouldMutate() throws {
        var vv1: VersionVector = VersionVector([
            (try self.replicaA.get(), VersionVector.Version(2)),
            (try self.replicaB.get(), VersionVector.Version(3)),
        ])
        let vv2: VersionVector = VersionVector([
            (try self.replicaA.get(), VersionVector.Version(1)),
            (try self.replicaB.get(), VersionVector.Version(4)),
            (try self.replicaC.get(), VersionVector.Version(5)),
        ])

        // Mutates vv1
        vv1.merge(other: vv2)

        vv1[try self.replicaA.get()].shouldEqual(2)  // 2 (vv1) > 1 (vv2)
        vv1[try self.replicaB.get()].shouldEqual(4)  // 4 (vv2) > 3 (vv1)
        vv1[try self.replicaC.get()].shouldEqual(5)  // From vv2

        // vv2 should remain the same
        vv2[try self.replicaA.get()].shouldEqual(1)
        vv2[try self.replicaB.get()].shouldEqual(4)
        vv2[try self.replicaC.get()].shouldEqual(5)
    }

    internal func test_VersionVector_contains() throws {
        let emptyVV: VersionVector = VersionVector()
        emptyVV.contains(try self.replicaA.get(), 0).shouldBeTrue()  // This is no version basically; always included
        emptyVV.contains(try self.replicaA.get(), 1).shouldBeFalse()

        let versionVector: VersionVector = VersionVector([
            (try self.replicaA.get(), VersionVector.Version(2)),
            (try self.replicaB.get(), VersionVector.Version(3)),
        ])
        versionVector.contains(try self.replicaA.get(), VersionVector.Version(1)).shouldBeTrue()  // 2 ≥ 1
        versionVector.contains(try self.replicaA.get(), VersionVector.Version(2)).shouldBeTrue()  // 2 ≥ 2
        versionVector.contains(try self.replicaA.get(), VersionVector.Version(3)).shouldBeFalse()  // 2 ≱ 3
        versionVector.contains(try self.replicaB.get(), VersionVector.Version(3)).shouldBeTrue()  // 3 ≥ 3
        versionVector.contains(try self.replicaB.get(), VersionVector.Version(4)).shouldBeFalse()  // 3 ≱ 4
        versionVector.contains(try self.replicaC.get(), VersionVector.Version(2)).shouldBeFalse()  // "C" not in vv
    }

    internal func test_VersionVector_compareTo_happenedBefore() throws {
        guard
            case .happenedBefore = VersionVector().compareTo(
                VersionVector([
                    (try self.replicaA.get(), VersionVector.Version(2))
                ])
            )
        else {
            throw shouldNotHappen("An empty version vector is always before a non-empty one")
        }
        guard
            case .happenedBefore = VersionVector([
                (try self.replicaA.get(), VersionVector.Version(1)),
                (try self.replicaB.get(), VersionVector.Version(2)),
            ])
            .compareTo(
                VersionVector([
                    (try self.replicaA.get(), VersionVector.Version(2)),
                    (try self.replicaB.get(), VersionVector.Version(3)),
                ])
            )
        else {
            throw shouldNotHappen(
                "Should be .happenedBefore relation since all entries "
                    + "in LHS are strictly less than RHS"
            )
        }
        guard
            case .happenedBefore = VersionVector([
                (try self.replicaA.get(), VersionVector.Version(1)),
                (try self.replicaB.get(), VersionVector.Version(1)),
                (try self.replicaC.get(), VersionVector.Version(1)),
            ])
            .compareTo(
                VersionVector([
                    (try self.replicaA.get(), VersionVector.Version(1)),
                    (try self.replicaB.get(), VersionVector.Version(1)),
                    (try self.replicaC.get(), VersionVector.Version(2)),
                ])
            )
        else {
            throw shouldNotHappen(
                "Should be .happenedBefore relation since 2 entries in LHS are "
                    + "equal, and at least one is strictly less than RHS"
            )
        }

    }

    internal func test_VersionVector_compareTo_happenedAfter() throws {
        guard
            case .happenedAfter = VersionVector([
                (try self.replicaA.get(), VersionVector.Version(2))
            ])
            .compareTo(VersionVector())
        else {
            throw shouldNotHappen("A non-empty version vector is always after an empty one")
        }
        guard
            case .happenedAfter = VersionVector([
                (try self.replicaA.get(), VersionVector.Version(2)),
                (try self.replicaB.get(), VersionVector.Version(3)),
            ])
            .compareTo(
                VersionVector([
                    (try self.replicaA.get(), VersionVector.Version(1)),
                    (try self.replicaB.get(), VersionVector.Version(2)),
                ])
            )
        else {
            throw shouldNotHappen(
                "Should be .happenedAfter relation since all entries "
                    + "in LHS are strictly greater than RHS"
            )
        }
        guard
            case .happenedAfter = VersionVector([
                (try self.replicaA.get(), VersionVector.Version(1)),
                (try self.replicaB.get(), VersionVector.Version(1)),
                (try self.replicaC.get(), VersionVector.Version(2)),
            ])
            .compareTo(
                VersionVector([
                    (try self.replicaA.get(), VersionVector.Version(1)),
                    (try self.replicaB.get(), VersionVector.Version(1)),
                    (try self.replicaC.get(), VersionVector.Version(1)),
                ])
            )
        else {
            throw shouldNotHappen(
                "Should be .happenedAfter relation since all entries "
                    + "in LHS are strictly greater than RHS"
            )
        }

    }

    internal func test_VersionVector_compareTo_sameOrConcurrent() throws {
        guard case .same = VersionVector().compareTo(VersionVector()) else {
            throw shouldNotHappen("Two empty version vectors should be considered the same")
        }
        guard
            case .same = VersionVector([
                (try self.replicaA.get(), VersionVector.Version(2)),
                (try self.replicaB.get(), VersionVector.Version(1)),
            ])
            .compareTo(
                VersionVector([
                    (try self.replicaB.get(), VersionVector.Version(1)),
                    (try self.replicaA.get(), VersionVector.Version(2)),
                ])
            )
        else {
            throw shouldNotHappen("Two version vectors should be considered the same if elements are equal")
        }

        guard
            case .concurrent = VersionVector([
                (try self.replicaA.get(), VersionVector.Version(1)),
                (try self.replicaB.get(), VersionVector.Version(4)),
                (try self.replicaC.get(), VersionVector.Version(6)),
            ])
            .compareTo(
                VersionVector([
                    (try self.replicaA.get(), VersionVector.Version(2)),
                    (try self.replicaB.get(), VersionVector.Version(7)),
                    (try self.replicaC.get(), VersionVector.Version(2)),
                ])
            )
        else {
            throw shouldNotHappen("Must be .concurrent relation if the two version vectors are not ordered or the same")
        }
        guard
            case .concurrent = VersionVector([
                (try self.replicaA.get(), VersionVector.Version(1))
            ])
            .compareTo(
                VersionVector([
                    (try self.replicaA.get(), VersionVector.Version(1)),
                    (try self.replicaB.get(), VersionVector.Version(1)),
                ])
            )
        else {
            throw shouldNotHappen(
                "Should be .concurrent, since even if rhs has more information, "
                    + "there is not at least `one strictly less than`"
            )
        }
    }

    // MARK: Dot tests

    internal func test_Dot_sort_shouldBeByReplicaThenByVersion() throws {
        let dot1: VersionDot = VersionDot(try self.replicaB.get(), VersionVector.Version(2))
        let dot2: VersionDot = VersionDot(try self.replicaA.get(), VersionVector.Version(3))
        let dot3: VersionDot = VersionDot(try self.replicaB.get(), VersionVector.Version(1))
        let dot4: VersionDot = VersionDot(try self.replicaC.get(), VersionVector.Version(5))
        let dots: Set<VersionDot> = [dot1, dot2, dot3, dot4]

        let sortedDots: [VersionDot] = dots.sorted()
        sortedDots.shouldEqual([dot2, dot3, dot1, dot4])
    }
}
// swiftlint:enable test_case_accessibility
