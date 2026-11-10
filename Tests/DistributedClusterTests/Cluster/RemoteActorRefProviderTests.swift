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

import DistributedActorsTestKit
import Foundation
import XCTest

@testable import DistributedCluster

internal final class RemoteActorRefProviderTests: SingleClusterSystemXCTestCase {

    override internal func setUp() async {
        _ = await self.setUpNode(String(reflecting: Self.self)) { settings in
            settings.enabled = true
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: resolve deadLetters

    internal func test_remoteActorRefProvider_shouldResolveDeadRef_forTypeMismatchOfActorAndResolveContext() throws {
        let ref: ActorRef<String> = try system.spawn("ignoresStrings", .stop)
        var id: ActorID = ref.id
        id.location = .remote(self.system.settings.bindNode)

        let resolveContext: ResolveContext<Int> = ResolveContext<Int>(id: id, system: system)
        let resolvedRef: ActorRef<Int> = self.system.resolve(context: resolveContext)

        "\(resolvedRef)".shouldEqual("ActorRef<Int>(/dead/user/ignoresStrings)")
    }

    internal
    func test_remoteActorRefProvider_shouldResolveSameAsLocalNodeDeadLettersRef_forTypeMismatchOfActorAndResolveContext(
    ) {
        let ref: ActorRef<DeadLetter> = self.system.deadLetters
        var id: ActorID = ref.id
        id.location = .remote(self.system.settings.bindNode)

        let resolveContext: ResolveContext<DeadLetter> = ResolveContext<DeadLetter>(id: id, system: system)
        let resolvedRef: ActorRef<DeadLetter> = self.system.resolve(context: resolveContext)

        "\(resolvedRef)".shouldEqual("ActorRef<DeadLetter>(/dead/letters)")
    }

    internal
    func test_remoteActorRefProvider_shouldResolveRemoteDeadLettersRef_forTypeMismatchOfActorAndResolveContext(
    ) {
        let ref: ActorRef<DeadLetter> = self.system.deadLetters
        var id: ActorID = ref.id
        let unknownNode: Cluster.Node =
            Cluster.Node(
                endpoint: .init(systemName: "something", host: "1.1.1.1", port: 1_111),
                nid: Cluster.Node.Identifier(1_211)
            )
        id.location = .remote(unknownNode)

        let resolveContext: ResolveContext<DeadLetter> = ResolveContext<DeadLetter>(id: id, system: system)
        let resolvedRef: ActorRef<DeadLetter> = self.system.resolve(context: resolveContext)

        "\(resolvedRef)".shouldEqual("ActorRef<DeadLetter>(sact://something@1.1.1.1:1111/dead/letters)")
    }

    internal
    func test_remoteActorRefProvider_shouldResolveRemoteAlreadyDeadRef_forTypeMismatchOfActorAndResolveContext(
    ) throws {
        let unknownNode: Cluster.Node =
            Cluster.Node(
                endpoint: .init(systemName: "something", host: "1.1.1.1", port: 1_111),
                nid: Cluster.Node.Identifier(1_211)
            )
        let id: ActorID =
            try .init(remote: unknownNode, path: ActorPath.dead.appending("already"), incarnation: .wellKnown)

        let resolveContext: ResolveContext<DeadLetter> = ResolveContext<DeadLetter>(id: id, system: system)
        let resolvedRef: ActorRef<DeadLetter> = self.system.resolve(context: resolveContext)

        "\(resolvedRef)".shouldEqual("ActorRef<DeadLetter>(sact://something@1.1.1.1:1111/dead/already)")
    }

    internal func test_remoteActorRefProvider_shouldResolveDeadRef_forSerializedDeadLettersRef() {
        let ref: ActorRef<String> = self.system.deadLetters.adapt(from: String.self)

        var id: ActorID = ref.id
        id.location = .remote(self.system.settings.bindNode)

        let resolveContext: ResolveContext<String> = ResolveContext<String>(id: id, system: system)
        let resolvedRef: ActorRef<String> = self.system.resolve(context: resolveContext)

        // then
        pinfo("Made remote ref: \(resolvedRef)", file: #fileID, line: #line)
        "\(resolvedRef)".shouldEqual("ActorRef<String>(/dead/letters)")
    }
}
