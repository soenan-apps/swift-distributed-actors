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

internal final class TraversalTests: SingleClusterSystemXCTestCase {
    internal struct ActorReady: Codable {
        internal let name: String
    }

    override internal func setUp() async throws {
        try await super.setUp()

        // we use the probe to make sure all actors are started before we start asserting on the tree
        let probe: ActorTestProbe<ActorReady> = self.testKit.makeTestProbe(expecting: ActorReady.self)

        let tellProbeWhenReady: Behavior<Int> = .setup { context in
            probe.tell(ActorReady(name: context.name))
            return .receiveMessage { _ in .same }
        }

        let _: ActorRef<String> = try self.system.spawn(
            "hello",

            .setup { context in
                probe.tell(ActorReady(name: context.name))
                let _: ActorRef<Int> = try context.spawn("world", tellProbeWhenReady)
                return .receiveMessage { _ in .same }
            }
        )

        let _: ActorRef<String> = try self.system.spawn(
            "other",

            .setup { context in
                probe.tell(ActorReady(name: context.name))
                let _: ActorRef<Int> = try context.spawn("inner-1", tellProbeWhenReady)
                let _: ActorRef<Int> = try context.spawn("inner-2", tellProbeWhenReady)
                let _: ActorRef<Int> = try context.spawn("inner-3", tellProbeWhenReady)
                return .receiveMessage { _ in .same }
            }
        )

        // once we get all ready messages here, we know the tree is "ready" and the tests which perform assertions on it
        // can run
        _ = try probe.expectMessages(count: 6)
        probe.stop()  // stopping a probe however is still asynchronous...
        // thus we make use of the fact we know probe internals and that the expectNoMessage still will work in this
        // situation
        try probe.expectNoMessage(for: .milliseconds(300))
    }

    internal func test_printTree_shouldPrintActorTree() {
        self.system.printTree()
    }

    internal func test_traverse_shouldAllowImplementingCollect() {
        let found: TraversalResult<String> = self.system.traverseAll { _, ref in
            if ref.id.name.contains("inner") {
                // collect it
                return .accumulateSingle(ref.id.name)
            }
            return .continue
        }

        switch found {
        case .results(let inners):
            inners.shouldContain("inner-1")
            inners.shouldContain("inner-2")
            inners.shouldContain("inner-3")
            inners.count.shouldEqual(3)

        default:
            fatalError("Should never happen. Traversal should have returned only the inner ones. Was: \(found)")
        }
    }

    internal func test_traverse_shouldHaveRightDepthInContext() {
        let _: TraversalResult<String> = self.system.traverseAll { context, ref in
            if ref.id.name == "hello" {
                context.depth.shouldEqual(1)
                return .continue
            }
            if ref.id.name == "world" {
                context.depth.shouldEqual(2)
                return .continue
            }
            return .continue
        }
    }
}
