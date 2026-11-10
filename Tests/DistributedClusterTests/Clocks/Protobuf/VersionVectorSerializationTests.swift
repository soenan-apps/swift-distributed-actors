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

import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

internal final class VersionVectorSerializationTests: SingleClusterSystemXCTestCase {
    internal var node: Cluster.Node {
        self.system.cluster.node
    }

    internal lazy var idA: Result<ActorID, any Error> = Result {
        try ActorID(local: node, path: ActorPath.userRoot.appending("A"), incarnation: .wellKnown)
    }
    internal lazy var idB: Result<ActorID, any Error> = Result {
        try ActorID(local: node, path: ActorPath.userRoot.appending("B"), incarnation: .wellKnown)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: VersionVector

    internal func test_serializationOf_VersionVector() throws {
        let versionVector: VersionVector = VersionVector([
            (.actorID(try self.idA.get()), 2), (.actorID(try self.idB.get()), 5)
        ])

        let serialized: Serialization.Serialized = try system.serialization.serialize(versionVector)
        let deserialized: VersionVector = try system.serialization.deserialize(as: VersionVector.self, from: serialized)

        deserialized.state.count.shouldEqual(2)  // replicas A and B
        "\(deserialized)".shouldContain("actor:sact://VersionVectorSerializationTests@127.0.0.1:9001/user/A: 2")
        "\(deserialized)".shouldContain("actor:sact://VersionVectorSerializationTests@127.0.0.1:9001/user/B: 5")
    }

    internal func test_serializationOf_VersionVector_empty() throws {
        let versionVector: VersionVector = VersionVector()

        let serialized: Serialization.Serialized = try system.serialization.serialize(versionVector)
        let deserialized: VersionVector = try system.serialization.deserialize(as: VersionVector.self, from: serialized)

        deserialized.isEmpty.shouldBeTrue()
    }

    // ==== -----------------------------------------------------------------------------------------------------------
    // MARK: VersionDot

    internal func test_serializationOf_VersionDot() throws {
        let dot: VersionDot = VersionDot(.actorID(try self.idA.get()), 2)

        let serialized: Serialization.Serialized = try system.serialization.serialize(dot)
        let deserialized: VersionDot = try system.serialization.deserialize(as: VersionDot.self, from: serialized)

        "\(deserialized)".shouldContain("actor:sact://VersionVectorSerializationTests@127.0.0.1:9001/user/A")
        deserialized.version.shouldEqual(2)
    }
}
