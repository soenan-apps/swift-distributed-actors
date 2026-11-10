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
//

import DistributedActorsTestKit
import Foundation
import NIO
import NIOFoundationCompat
import XCTest

@testable import DistributedCluster

extension SerializationTests {
    internal func test_serialize_Bool_withData() throws {
        let value: Bool = true

        let serialized: Serialization.Serialized = try system.serialization.serialize(value)
        // Deserialize from `Data`
        let deserialized: Bool = try system.serialization.deserialize(
            as: Bool.self,
            from: .data(
                serialized.buffer.readData()
            ),
            using: serialized.manifest
        )

        deserialized.shouldEqual(value)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Codable round-trip tests for of simple Swift Distributed Actors types

    internal func test_serialize_actorPath() throws {
        let path: ActorPath = try ActorPath(root: "user") / ActorPathSegment("hello")
        let encoded: Data = try JSONEncoder().encode(path)
        pinfo(
            "Serialized actor path: \(encoded.copyToNewByteBuffer().stringDebugDescription())",
            file: #fileID,
            line: #line
        )

        let pathAgain: ActorPath = try JSONDecoder().decode(ActorPath.self, from: encoded)
        pinfo("Deserialized again: \(String(reflecting: pathAgain))", file: #fileID, line: #line)

        pathAgain.shouldEqual(path)
    }

    internal func test_serialize_actorAddress_usingContext() throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "one",
            host: "127.0.0.1",
            port: 1_234,
            nid: Cluster.Node.Identifier(11_111)
        )
        let id: ActorID = try ActorPath(root: "user").appending("hello").makeLocalID(on: node, incarnation: .random())

        let encoder: JSONEncoder = JSONEncoder()
        let decoder: JSONDecoder = JSONDecoder()

        let context: Serialization.Context = Serialization.Context(
            log: self.system.log,

            system: self.system,

            allocator: ByteBufferAllocator()
        )

        encoder.userInfo[.actorSerializationContext] = context
        decoder.userInfo[.actorSerializationContext] = context

        let encoded: Data = try encoder.encode(id)
        pinfo(
            "Serialized actor path: \(encoded.copyToNewByteBuffer().stringDebugDescription())",
            file: #fileID,
            line: #line
        )

        let decodedID: ActorID = try decoder.decode(ActorID.self, from: encoded)
        pinfo("Deserialized again: \(String(reflecting: decodedID))", file: #fileID, line: #line)

        "\(decodedID)".shouldEqual("sact://one@127.0.0.1:1234/user/hello")
        decodedID.incarnation.shouldEqual(id.incarnation)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Actor ref serialization and resolve

    internal func test_serialize_actorRef_inMessage() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)

        let ref: ActorRef<String> = try system.spawn(
            "hello",

            .receiveMessage { message in
                probe.tell("got:\(message)")
                return .same
            }
        )
        let hasRef: HasStringRef = HasStringRef(containedRef: ref)

        pinfo("Before serialize: \(hasRef)", file: #fileID, line: #line)

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(hasRef)
        }
        pinfo("serialized ref: \(serialized.buffer.stringDebugDescription())", file: #fileID, line: #line)

        let back: HasStringRef = try shouldNotThrow {
            try system.serialization.deserialize(as: HasStringRef.self, from: serialized)
        }
        pinfo("Deserialized again: \(back)", file: #fileID, line: #line)

        back.shouldEqual(hasRef)

        back.containedRef.tell("hello")
        try probe.expectMessage("got:hello")
    }

}
