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

internal final class ActorIDTests: ClusteredActorSystemsXCTestCase {
    internal func test_local_actorAddress_shouldPrintNicely() throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "\(Self.self)",
            host: "127.0.0.1",
            port: 7_337,
            nid: .random()
        )
        let id: ActorID = try ActorID(
            local: node,
            path: ActorPath.userRoot.appending("hello"),
            incarnation: ActorIncarnation(8_888)
        )
        "\(id)".shouldEqual("/user/hello")
        "\(id.name)".shouldEqual("hello")
        "\(id.path)".shouldEqual("/user/hello")
        "\(id.path.name)".shouldEqual("hello")
        "\(id.path)".shouldEqual("/user/hello")
        "\(id.path.name)".shouldEqual("hello")

        id.detailedDescription.shouldEqual("/user/hello#8888[\"$path\": /user/hello]")
        String(reflecting: id).shouldEqual("/user/hello")
        String(reflecting: id.name).shouldEqual("\"hello\"")
        String(reflecting: id.path).shouldEqual("/user/hello")
        String(reflecting: id.path.name).shouldEqual("\"hello\"")
        String(reflecting: id.path).shouldEqual("/user/hello")
        String(reflecting: id.path.name).shouldEqual("\"hello\"")
    }

    internal func test_remote_actorAddress_shouldPrintNicely() throws {
        let localNode: Cluster.Node = Cluster.Node(
            systemName: "\(Self.self)",
            host: "127.0.0.1",
            port: 7_337,
            nid: .random()
        )
        let id: ActorID = try ActorID(
            local: localNode,
            path: ActorPath.userRoot.appending("hello"),
            incarnation: ActorIncarnation(8_888)
        )
        let remoteNode: Cluster.Node = Cluster.Node(
            systemName: "system",
            host: "127.0.0.1",
            port: 1_234,
            nid: Cluster.Node.Identifier(11_111)
        )
        let remote: ActorID = ActorID(remote: remoteNode, path: id.path, incarnation: ActorIncarnation(8_888))

        remote.detailedDescription.shouldEqual(
            "sact://system:11111@127.0.0.1:1234/user/hello#8888[\"$path\": /user/hello]"
        )
        String(reflecting: remote).shouldEqual("sact://system@127.0.0.1:1234/user/hello")
        "\(remote)".shouldEqual("sact://system@127.0.0.1:1234/user/hello")
        "\(remote.name)".shouldEqual("hello")
        "\(remote.path)".shouldEqual("/user/hello")
        "\(remote.path.name)".shouldEqual("hello")
        "\(remote.path)".shouldEqual("/user/hello")
        "\(remote.path.name)".shouldEqual("hello")
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Equality & Sorting

    internal func test_equalityOf_idWithSameSegmentsButDifferentIncarnation() throws {
        let node: Cluster.Node = Cluster.Node(
            systemName: "\(Self.self)",
            host: "127.0.0.1",
            port: 7_337,
            nid: .random()
        )
        let one: ActorID = try ActorPath(root: "test").makeChildPath(name: "foo").makeLocalID(
            on: node,
            incarnation: .random()
        )
        let two: ActorID = try ActorPath(root: "test").makeChildPath(name: "foo").makeLocalID(
            on: node,
            incarnation: .random()
        )

        one.shouldNotEqual(two)
        one.incarnation.shouldNotEqual(two.incarnation)

        // their "uid-less" parts though are equal
        one.path.shouldEqual(two.path)
    }

    internal func test_equalityOf_idWithDifferentSystemNameOnly() throws {
        let path: ActorPath = try ActorPath.userRoot.appending("hello")
        let one: ActorID = ActorID(
            local: Cluster.Node(
                systemName: "one",
                host: "127.0.0.1",
                port: 1_234,
                nid: Cluster.Node.Identifier(11_111)
            ),
            path: path,
            incarnation: ActorIncarnation(88)
        )
        let two: ActorID = ActorID(
            local: Cluster.Node(
                systemName: "two",
                host: "127.0.0.1",
                port: 1_234,
                nid: Cluster.Node.Identifier(11_111)
            ),
            path: path,
            incarnation: ActorIncarnation(88)
        )

        one.shouldEqual(two)
    }

    internal func test_equalityOf_idWithDifferentSystemNameOnly_remote() throws {
        let path: ActorPath = try ActorPath.userRoot.appending("hello")
        let one: ActorID = ActorID(
            remote: Cluster.Node(
                systemName: "one",
                host: "127.0.0.1",
                port: 1_234,
                nid: Cluster.Node.Identifier(11_111)
            ),
            path: path,
            incarnation: ActorIncarnation(88)
        )
        let two: ActorID = ActorID(
            remote: Cluster.Node(
                systemName: "two",
                host: "127.0.0.1",
                port: 1_234,
                nid: Cluster.Node.Identifier(11_111)
            ),
            path: path,
            incarnation: ActorIncarnation(88)
        )

        one.shouldEqual(two)
    }

    internal func test_equalityOf_idWithDifferentSystemNameOnly_local_remote() throws {
        let path: ActorPath = try ActorPath.userRoot.appending("hello")
        let one: ActorID = ActorID(
            local: Cluster.Node(
                systemName: "one",
                host: "127.0.0.1",
                port: 1_234,
                nid: Cluster.Node.Identifier(11_111)
            ),
            path: path,
            incarnation: ActorIncarnation(88)
        )
        let two: ActorID = ActorID(
            remote: Cluster.Node(
                systemName: "two",
                host: "127.0.0.1",
                port: 1_234,
                nid: Cluster.Node.Identifier(11_111)
            ),
            path: path,
            incarnation: ActorIncarnation(88)
        )

        one.shouldEqual(two)
    }

}

extension ActorMetadataKeys {
    internal var test: Key<String> { "$test" }
}
