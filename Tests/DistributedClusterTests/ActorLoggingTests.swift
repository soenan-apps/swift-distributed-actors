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
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

private enum Rendered: String, Codable {
    case instance = "instance"
}

internal final class ActorLoggingTests: SingleClusterSystemXCTestCase {

    internal func test_actorLogger_shouldIncludeActorPath() throws {
        let senderPath: ActorPath = try ActorPath(root: "user")
            .appending("hello").appending("deep").appending("path").appending("avoid-rendering-this-if-possible")
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe("p", expecting: String.self)
        let resultProbe: ActorTestProbe<Rendered> = self.testKit.makeTestProbe("r", expecting: Rendered.self)

        let ref: ActorRef<String> = try system.spawn(
            "myName",

            .setup { context in
                // ~~~~~~~ (imagine as) set by swift-distributed-actors library internally ~~~~~~~~~~
                context.log[metadataKey: "senderPath"] = .lazyStringConvertible {
                    resultProbe.ref.tell(.instance)
                    return senderPath.description
                }
                // ~~~~ end of (imagine as) set by swift-distributed-actors library internally ~~~~~~

                return .receiveMessage { message in
                    context.log.info("I got \(message)")

                    probe.ref.tell("Got: \(message)")
                    return .same
                }
            }
        )

        ref.tell("Hello world")
        try probe.expectMessage("Got: Hello world")
        // try r.expectNoMessage(for: .milliseconds(100))
    }

    internal func test_actorLogger_shouldNotRenderLazyMetadataIfLogIsUnderDefinedLogLevel() throws {
        let senderPath: ActorPath = try ActorPath(root: "user")
            .appending("hello").appending("deep").appending("path").appending("avoid-rendering-this-if-possible")
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe("p2", expecting: String.self)
        let resultProbe: ActorTestProbe<Rendered> = self.testKit.makeTestProbe("r2", expecting: Rendered.self)

        let ref: ActorRef<String> = try system.spawn(
            "myName",

            .setup { context in
                // ~~~~~~~ (imagine as) set by swift-distributed-actors library internally ~~~~~~~~~~
                context.log[metadataKey: "senderPath"] = .lazyStringConvertible {
                    resultProbe.ref.tell(.instance)
                    return senderPath.description
                }
                // ~~~~ end of (imagine as) set by swift-distributed-actors library internally ~~~~~~

                return .receiveMessage { message in
                    context.log.logLevel = .warning
                    context.log.info("I got \(message)")  // thus should not render any metadata

                    probe.ref.tell("Got: \(message)")
                    return .same
                }
            }
        )

        ref.tell("Hello world")
        try probe.expectMessage("Got: Hello world")
        try resultProbe.expectNoMessage(for: .milliseconds(100))
    }

    internal func test_actorLogger_shouldNotRenderALazyValueIfWeOverwriteItUsingLocalMetadata() throws {
        let senderPath: ActorPath = try ActorPath(root: "user")
            .appending("hello").appending("deep").appending("path").appending("avoid-rendering-this-if-possible")
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe("p2", expecting: String.self)
        let resultProbe: ActorTestProbe<Rendered> = self.testKit.makeTestProbe("r2", expecting: Rendered.self)

        let ref: ActorRef<String> = try system.spawn(
            "myName",

            .setup { context in
                // ~~~~~~~ (imagine as) set by swift-distributed-actors library internally ~~~~~~~~~~
                context.log[metadataKey: "senderPath"] = .lazyStringConvertible {
                    resultProbe.ref.tell(.instance)
                    return senderPath.description
                }
                // ~~~~ end of (imagine as) set by swift-distributed-actors library internally ~~~~~~

                return .receiveMessage { message in
                    // overwrite the metadata with a local one:
                    context.log.info("I got \(message)", metadata: ["senderPath": .string("/user/sender/pre-rendered")])

                    probe.ref.tell("Got: \(message)")
                    return .same
                }
            }
        )

        ref.tell("Hello world")
        try probe.expectMessage("Got: Hello world")
        try resultProbe.expectNoMessage(for: .milliseconds(100))
    }
}
