// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
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

extension ActorIDTests {
    internal func test_equalityOf_idWithDifferentSegmentsButSameUID() throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "one",
            host: "127.0.0.1",
            port: 1_234,
            nid: Cluster.Node.Identifier(11_111)
        )
        let one: ActorID = try ActorPath(root: "test").makeChildPath(name: "foo").makeLocalID(
            on: node,
            incarnation: .random()
        )
        let one2: ActorID = try ActorPath(root: "test").makeChildPath(name: "foo2").makeLocalID(
            on: node,
            incarnation: one.incarnation
        )

        one.shouldNotEqual(one2)
    }

    internal func test_sortingOf_actorIDs() throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "one",
            host: "127.0.0.1",
            port: 1_234,
            nid: Cluster.Node.Identifier(11_111)
        )
        var ids: [ActorID] = []
        let firstValue: ActorID = try ActorPath.userRoot.appending("a").makeLocalID(on: node, incarnation: .random())
        let secondValue: ActorID = try ActorPath.userRoot.appending("b").makeLocalID(on: node, incarnation: .random())
        let thirdValue: ActorID = try ActorPath.userRoot.appending("c").makeLocalID(on: node, incarnation: .random())
        ids.append(thirdValue)
        ids.append(secondValue)
        ids.append(firstValue)

        // sorting should not be impacted by the random incarnation numbers
        ids.sorted().shouldEqual([firstValue, secondValue, thirdValue])
    }

    internal func test_sortingOf_sameNode_actorIDs() throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "one",
            host: "127.0.0.1",
            port: 1_234,
            nid: Cluster.Node.Identifier(11_111)
        )
        var ids: [ActorID] = []
        let firstValue: ActorID = try ActorPath.userRoot.appending("a").makeLocalID(on: node, incarnation: .wellKnown)
        let secondValue: ActorID = try ActorPath.userRoot.appending("b").makeLocalID(on: node, incarnation: .wellKnown)
        let thirdValue: ActorID = try ActorPath.userRoot.appending("c").makeLocalID(on: node, incarnation: .wellKnown)
        ids.append(thirdValue)
        ids.append(secondValue)
        ids.append(firstValue)

        // sorting should not be impacted by the random incarnation numbers
        ids.sorted().shouldEqual([firstValue, secondValue, thirdValue])
    }

    internal func test_sortingOf_diffNodes_actorIDs() throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "one",
            host: "127.0.0.1",
            port: 1_234,
            nid: Cluster.Node.Identifier(11_111)
        )
        var ids: [ActorID] = []
        let firstValue: ActorID = try ActorPath.userRoot.appending("a").makeRemoteID(on: node, incarnation: 1)
        let secondValue: ActorID = try ActorPath.userRoot.appending("a").makeRemoteID(on: node, incarnation: 1)
        let thirdValue: ActorID = try ActorPath.userRoot.appending("a").makeRemoteID(on: node, incarnation: 1)
        ids.append(thirdValue)
        ids.append(secondValue)
        ids.append(firstValue)

        // sorting should not be impacted by the random incarnation numbers
        ids.sorted().shouldEqual([firstValue, secondValue, thirdValue])
    }

    // ==== -----------------------------------------------------------------------------------------------------------
    // MARK: Coding

    internal func test_encodeDecode_ActorAddress_withoutSerializationContext() throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "one",
            host: "127.0.0.1",
            port: 1_234,
            nid: Cluster.Node.Identifier(11_111)
        )
        let firstValue: ActorID = try ActorPath.userRoot.appending("a").makeRemoteID(on: node, incarnation: 1)
        let addressWithoutTestTag: ActorID = firstValue
        firstValue.metadata.test = "test-value"

        let data: Data = try JSONEncoder().encode(
            firstValue
        )  // should skip the test tag, it does not know how to encode it
        let serializedJson: String = try XCTUnwrap(String(data: data, encoding: .utf8))

        serializedJson.shouldContain(#""incarnation":1"#)
        serializedJson.shouldContain(#""node":["sact","one","127.0.0.1",1234,11111]"#)
        serializedJson.shouldContain(#""path":{"path":["user","a"]}"#)
        serializedJson.shouldNotContain(
            #"$test":"test-value""#
        )

        let back: ActorID = try JSONDecoder().decode(ActorID.self, from: data)
        back.shouldEqual(addressWithoutTestTag)
    }

    internal func test_serializing_ActorAddress_skipCustomTag() async throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "one",
            host: "127.0.0.1",
            port: 1_234,
            nid: Cluster.Node.Identifier(11_111)
        )
        let firstValue: ActorID = try ActorPath.userRoot.appending("a").makeRemoteID(on: node, incarnation: 1)
        firstValue.metadata.test = "test-value"

        let system: ClusterSystem = await self.setUpNode("test_serializing_ActorAddress_skipCustomTag") { settings in
            settings.bindPort = 1_234
        }

        let serialized: Serialization.Serialized = try system.serialization.serialize(firstValue)
        let serializedJson: String = try XCTUnwrap(String(data: serialized.buffer.readData(), encoding: .utf8))

        // improve serialization format of identities to be more compact
        serializedJson.shouldContain(#""incarnation":1"#)
        serializedJson.shouldContain(#""node":["sact","one","127.0.0.1",1234,11111]"#)
        serializedJson.shouldContain(#""path":{"path":["user","a"]}"#)
        serializedJson.shouldNotContain(
            #"$test":"test-value""#
        )
    }

    internal func test_serializing_ActorAddress_propagateCustomTag() async throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "one",
            host: "127.0.0.1",
            port: 1_234,
            nid: Cluster.Node.Identifier(11_111)
        )
        let firstValue: ActorID = try ActorPath.userRoot.appending("a").makeRemoteID(on: node, incarnation: 1)
        firstValue.metadata.test = "test-value"

        let system: ClusterSystem = await self.setUpNode(
            "test_serializing_ActorAddress_propagateCustomTag"
        ) { settings in
            settings.bindPort = 1_234
            settings.actorMetadata.encodeCustomMetadata = { metadata, container in
                try container.encodeIfPresent(
                    metadata.test,
                    forKey: ActorCoding.MetadataKeys.custom(
                        ActorMetadataKeys.defaultInstance.test.id
                    )
                )
            }

            settings.actorMetadata.decodeCustomMetadata = { container, metadata in
                if let value = try container.decodeIfPresent(
                    String.self,
                    forKey: .custom(
                        ActorMetadataKeys.defaultInstance.test.id
                    )
                ) {
                    metadata.test = value
                }
            }
        }

        let serialized: Serialization.Serialized = try system.serialization.serialize(firstValue)
        let serializedJson: String = try XCTUnwrap(String(data: serialized.buffer.readData(), encoding: .utf8))

        // improve serialization format of identities to be more compact
        serializedJson.shouldContain(#""incarnation":1"#)
        serializedJson.shouldContain(#""node":["sact","one","127.0.0.1",1234,11111]"#)
        serializedJson.shouldContain(#""path":{"path":["user","a"]}"#)
        try serializedJson.shouldContain(
            "\"\(ActorMetadataKeys.defaultInstance.test.id)\":\"\(XCTUnwrap(firstValue.metadata.test))\""
        )
    }
}
