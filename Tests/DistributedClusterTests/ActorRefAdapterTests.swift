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

internal class ActorRefAdapterTests: SingleClusterSystemXCTestCase {
    internal enum LifecycleTestMessage: NotActuallyCodableMessage {
        case createAdapter(replyTo: ActorRef<ActorRef<String>>)
        case crash
        case stop
        case message(String)
    }

    internal func test_adaptedRef_shouldConvertMessages() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let refProbe: ActorTestProbe<ActorRef<Int>> = self.testKit.makeTestProbe(expecting: ActorRef<Int>.self)

        let behavior: Behavior<String> = .setup { context in
            refProbe.tell(context.messageAdapter { "\($0)" })
            return .receiveMessage { msg in
                probe.ref.tell(msg)
                return .same
            }
        }

        _ = try self.system.spawn(.anonymous, behavior)

        let adapted: ActorRef<Int> = try refProbe.expectMessage()

        for index in 0...10 {
            adapted.tell(index)
        }

        for index in 0...10 {
            try probe.expectMessage("\(index)")
        }
    }

    internal func test_adaptedRef_overNetwork_shouldConvertMessages() async throws {
        let firstSystem: ClusterSystem = await setUpNode("One-RemoteActorRefAdapterTests") { settings in
            settings.enabled = true
            settings.endpoint.host = "127.0.0.1"
            settings.endpoint.port = 1_881
        }
        let firstTestKit: ActorTestKit = self.testKit(firstSystem)
        let probe: ActorTestProbe<String> = firstTestKit.makeTestProbe(expecting: String.self)
        let refProbe: ActorTestProbe<ActorRef<Int>> = firstTestKit.makeTestProbe(expecting: ActorRef<Int>.self)

        let systemTwo: ClusterSystem = await setUpNode("Two-RemoteActorRefAdapterTests") { settings in
            settings.enabled = true
            settings.endpoint.host = "127.0.0.1"
            settings.endpoint.port = 1_991
        }

        firstSystem.cluster.join(endpoint: systemTwo.settings.endpoint)

        sleep(2)

        let behavior: Behavior<String> = .setup { context in
            refProbe.tell(context.messageAdapter { "\($0)" })
            return .receiveMessage { msg in
                probe.ref.tell(msg)
                return .same
            }
        }

        _ = try systemTwo.spawn("target", behavior)

        let adapted: ActorRef<Int> = try refProbe.expectMessage()

        for index in 0...10 {
            adapted.tell(index)
        }

        for index in 0...10 {
            try probe.expectMessage("\(index)")
        }
    }

    internal func test_adaptedRef_shouldBeWatchable() throws {
        let probe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(expecting: ActorRef<String>.self)

        let behavior: Behavior<Int> = .setup { context in
            probe.tell(context.messageAdapter { _ in 0 })
            return .receiveMessage { _ in
                .stop
            }
        }

        try system.spawn(.anonymous, behavior)

        let adaptedRef: ActorRef<String> = try probe.expectMessage()

        probe.watch(adaptedRef)

        adaptedRef.tell("test")

        try probe.expectTerminated(adaptedRef)
    }

}
