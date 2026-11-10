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

import Dispatch
import DistributedActorsTestKit
import Foundation
import Logging
import NIO
import XCTest

@testable import DistributedCluster

internal final class DispatcherTests: SingleClusterSystemXCTestCase {
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Running "on NIO" for fun and profit

    internal func test_runOn_nioEventLoop() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let behavior: Behavior<String> = .receive { context, message in
            context.log.info("HELLO")
            probe.tell("Received: \(message)")
            probe.tell("Dispatcher: \((try XCTUnwrap(context as? ActorShell<String>)).messageDispatcher.name)")
            return .same
        }

        let worker: ActorRef<String> = try system.spawn(
            .anonymous,
            behavior,
            props: .dispatcher(
                .nio(
                    self.eventLoopGroup.next()
                )
            )
        )
        worker.tell("Hello")

        let received: String = try probe.expectMessage()
        received.dropFirst("Received: ".count).shouldEqual("Hello")

        let dispatcher: String = try probe.expectMessage()
        dispatcher.dropFirst("Dispatcher: ".count).shouldStartWith(prefix: "nio:")
    }

    internal func test_runOn_nioEventLoopGroup() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let behavior: Behavior<String> = .receive { context, message in
            context.log.info("HELLO")
            probe.tell("Received: \(message)")
            probe.tell("Dispatcher: \((try XCTUnwrap(context as? ActorShell<String>)).messageDispatcher.name)")
            return .same
        }

        let worker: ActorRef<String> = try system.spawn(
            .anonymous,
            behavior,
            props: .dispatcher(
                .nio(
                    self.eventLoopGroup
                )
            )
        )
        worker.tell("Hello")

        let received: String = try probe.expectMessage()
        received.dropFirst("Received: ".count).shouldEqual("Hello")

        let dispatcher: String = try probe.expectMessage()
        dispatcher.dropFirst("Dispatcher: ".count).shouldStartWith(prefix: "nio:")
    }

    // ====
    // ----------------------------------------------------------------------------------------------------------------
    // MARK: Grand Central Dispatch

    internal func test_runOn_dispatchQueue() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let behavior: Behavior<String> = .receive { context, message in
            context.log.info("HELLO")
            probe.tell("\(message)")
            probe.tell("\((try XCTUnwrap(context as? ActorShell<String>)).messageDispatcher.name)")
            return .same
        }

        let global: DispatchQueue = .global()
        let worker: ActorRef<String> = try system.spawn(
            .anonymous,
            behavior,
            props: .dispatcher(
                .dispatchQueue(
                    global
                )
            )
        )
        worker.tell("Hello")
        worker.tell("World")

        func expectWasOnDispatchQueue(probe: ActorTestProbe<String>) throws {
            #if os(Linux)
            try probe.expectMessage().shouldContain("Dispatch.DispatchQueue")
            #else
            try probe.expectMessage().shouldContain("OS_dispatch_queue_global:")
            #endif
        }

        try probe.expectMessage("Hello")
        try expectWasOnDispatchQueue(probe: probe)

        try probe.expectMessage("World")
        try expectWasOnDispatchQueue(probe: probe)

        for index in 1...100 {
            worker.tell("\(index)")
        }
        for index in 1...100 {
            try probe.expectMessage("\(index)")
            try expectWasOnDispatchQueue(probe: probe)
        }
    }
}
