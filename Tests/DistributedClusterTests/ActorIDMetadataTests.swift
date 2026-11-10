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

import Distributed
import DistributedActorsTestKit
import NIOCore
import XCTest

@testable import DistributedCluster

public protocol ExampleClusterSingleton: DistributedActor {
    var exampleSingletonID: String { get }

    // Must be implemented by providing a metadata property wrapper.
    // var _singletonID: ActorID.Metadata<String, ActorMetadata.ExampleClusterSingletonIDTag.Key> { get } // property
    // wrapper bug? Property '_singletonID' must be as accessible as its enclosing type because it matches a requirement
    // in protocol 'ClusterSingleton'
}

internal distributed actor ThereCanBeOnlyOneClusterSingleton: ExampleClusterSingleton {
    internal typealias ActorSystem = ClusterSystem

    @ActorID.Metadata(\.wellKnown)
    internal var wellKnownName: String

    @ActorID.Metadata(\.exampleClusterSingletonID)
    internal var exampleSingletonID: String
    // impossible to assign initial value here, as _enclosingInstance is not available yet "the-one"

    internal init(actorSystem: ActorSystem) async {
        self.actorSystem = actorSystem
        self.exampleSingletonID = "singer-1234"
        self.wellKnownName = "singer-1234"
    }
}

internal distributed actor MetadataExampleActor: CustomStringConvertible {
    internal typealias ActorSystem = ClusterSystem

    @ActorID.Metadata(\.exampleUserID)
    internal var userID: String

    nonisolated internal var description: String {
        "\(Self.self)(\(self.metadata))"
    }

    internal init(userID: String, actorSystem: ActorSystem) async {
        self.actorSystem = actorSystem
        self.userID = userID
    }

    internal distributed func assertThat(userID: String) {
        assert(self.userID == userID)
    }

}

internal final class ActorIDMetadataTests: ClusteredActorSystemsXCTestCase {

    internal func test_metadata_shouldBeStoredInID() async {
        let system: ClusterSystem = await setUpNode("first")
        let userID: String = "user-1234"
        let example: MetadataExampleActor = await MetadataExampleActor(userID: userID, actorSystem: system)

        example.metadata.exampleUserID.shouldEqual(userID)
    }

    internal func test_metadata_beUsableInDescription() async throws {
        let system: ClusterSystem = await setUpNode("first")
        let userID: String = "user-1234"
        let example: MetadataExampleActor = await MetadataExampleActor(userID: userID, actorSystem: system)

        "\(example)".shouldContain("\"user-id\": \"user-1234\"")
        try await example.assertThat(userID: userID)
    }

    internal func test_metadata_initializedInline() async {
        let system: ClusterSystem = await setUpNode("first")
        let singleton: ThereCanBeOnlyOneClusterSingleton = await ThereCanBeOnlyOneClusterSingleton(actorSystem: system)

        singleton.metadata.exampleClusterSingletonID.shouldEqual("singer-1234")
    }

    internal func test_metadata_wellKnown_coding() async throws {
        let system: ClusterSystem = await setUpNode("first")
        let singleton: ThereCanBeOnlyOneClusterSingleton = await ThereCanBeOnlyOneClusterSingleton(actorSystem: system)

        let encoded: Data = try JSONEncoder().encode(singleton)
        let encodedString: String = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        encodedString.shouldContain("\"$wellKnown\":\"singer-1234\"")

        let back: ActorID = try JSONDecoder().decode(ActorID.self, from: encoded)
        back.metadata.wellKnown.shouldEqual("singer-1234")
    }

    internal func test_metadata_wellKnown_proto() async throws {
        let system: ClusterSystem = await setUpNode("first")
        let singleton: ThereCanBeOnlyOneClusterSingleton = await ThereCanBeOnlyOneClusterSingleton(actorSystem: system)

        let context: Serialization.Context = Serialization.Context(log: system.log, system: system, allocator: .init())
        let encoded: ActorID.ProtobufRepresentation = try singleton.id.toProto(context: context)

        let back: ActorID = try ActorID(fromProto: encoded, context: context)
        back.metadata.wellKnown.shouldEqual(singleton.id.metadata.wellKnown)
    }

    internal func test_metadata_wellKnown_equality() async throws {
        let system: ClusterSystem = await setUpNode("first")

        let singleton: ThereCanBeOnlyOneClusterSingleton = await ThereCanBeOnlyOneClusterSingleton(actorSystem: system)

        let madeUpID: ActorID = ActorID(local: system.cluster.node, path: singleton.id.path, incarnation: .wellKnown)
        madeUpID.metadata.wellKnown = try XCTUnwrap(singleton.id.metadata.wellKnown)

        singleton.id.shouldEqual(madeUpID)
        singleton.id.hashValue.shouldEqual(madeUpID.hashValue)

        let set: Set<ActorID> = [singleton.id, madeUpID]
        set.count.shouldEqual(1)
    }

    internal func test_metadata_userDefined_coding() async throws {
        let system: ClusterSystem = await setUpNode("first")
        let singleton: ThereCanBeOnlyOneClusterSingleton = await ThereCanBeOnlyOneClusterSingleton(actorSystem: system)

        let encoded: Data = try JSONEncoder().encode(singleton)
        let encodedString: String = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        encodedString.shouldContain("\"$wellKnown\":\"singer-1234\"")

        let back: ActorID = try JSONDecoder().decode(ActorID.self, from: encoded)
        back.metadata.wellKnown.shouldEqual("singer-1234")
    }
}
extension ActorMetadataKeys {
    internal var exampleUserID: Key<String> { "user-id" }
    internal var exampleClusterSingletonID: Key<String> { "singleton-id" }
}
