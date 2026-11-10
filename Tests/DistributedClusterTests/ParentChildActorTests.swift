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
import Logging
import XCTest

@testable import DistributedCluster

internal final class ParentChildActorTests: SingleClusterSystemXCTestCase {
    internal typealias ParentRef = ActorRef<ParentProtocol>
    internal typealias ChildRef = ActorRef<ChildProtocol>
    internal typealias ParentChildProbeRef = ActorRef<ParentChildProbeProtocol>

    internal enum ParentProtocol: NotActuallyCodableMessage {
        case spawnChild(name: String, behavior: Behavior<ChildProtocol>)
        case spawnAnonymousChild(behavior: Behavior<ChildProtocol>)

        case stopByName(name: String)
        case findByName(name: String)
        case stop
    }

    internal enum ChildProtocol: NotActuallyCodableMessage {
        case howAreYou(replyTo: ActorRef<String>)
        case fail
        case throwWhoops
        case makeChild(name: String, behavior: Behavior<Self>)
    }

    internal enum ParentChildProbeProtocol: Equatable, NotActuallyCodableMessage {
        case spawned(child: ChildRef)
        case spawnFailed(path: ActorPath)

        case childNotFound(name: String)
        case childFound(name: String, ref: ChildRef)
        case childStopped(name: String)
    }

    internal enum ChildError: Error {
        case whoops
    }

    private func spawnChild<Message: Codable>(
        _ naming: ActorNaming,
        _ behavior: Behavior<ChildProtocol>,
        in context: ActorContext<Message>,
        probe: ParentChildProbeRef,
        watch watchChildren: Bool
    ) throws {
        do {
            let child: ChildRef = try context.spawn(naming, behavior)
            if watchChildren {
                context.watch(child)
            }
            probe.tell(.spawned(child: child))
        } catch let error as ActorContextError {
            if case .duplicateActorPath(let path, _) = error.underlying.error {
                probe.tell(.spawnFailed(path: path))
            } else {
                throw error
            }
        }
    }

    internal func parentBehavior(
        probe: ParentChildProbeRef,
        notifyWhenChildStops watchChildren: Bool = false
    ) -> Behavior<ParentProtocol> {
        Behavior<ParentProtocol>.receive { context, message in
            switch message {
            case .stop:
                return .stop

            case let .spawnChild(name, behavior):
                try self.spawnChild(.unique(name), behavior, in: context, probe: probe, watch: watchChildren)

            case .spawnAnonymousChild(let behavior):
                try self.spawnChild(.anonymous, behavior, in: context, probe: probe, watch: watchChildren)

            case .findByName(let name):
                if let found = context.children.find(named: name, withType: ChildProtocol.self) {
                    probe.tell(.childFound(name: name, ref: found))
                } else {
                    probe.tell(.childNotFound(name: name))
                }

            case .stopByName(let name):
                if let kid = context.children.find(named: name, withType: ChildProtocol.self) {
                    try context.stop(child: kid)
                    probe.tell(.childFound(name: name, ref: kid))
                } else {
                    probe.tell(.childNotFound(name: name))
                }
            }

            return .same
        }.receiveSignal { _, signal in
            switch signal {
            case let terminated as Signals.Terminated:
                if watchChildren {
                    probe.tell(.childStopped(name: terminated.id.name))
                }

            default:
                ()
            }
            return .same
        }
    }

    internal func childBehavior(
        probe: ParentChildProbeRef,
        notifyWhenChildStops watchChildren: Bool = false
    ) -> Behavior<ChildProtocol> {
        .setup { context in
            context.log.debug("Hello...")

            return .receiveMessage { message in
                switch message {
                case .howAreYou(let replyTo):
                    replyTo.tell("Pretty good, I'm \(context.path)")

                case .fail:
                    fatalError("Ohh no~!")

                case .throwWhoops:
                    throw ChildError.whoops

                case let .makeChild(name, behavior):
                    try self.spawnChild(.unique(name), behavior, in: context, probe: probe, watch: watchChildren)
                }
                return .same
            }
        }
    }

    internal func test_contextSpawn_shouldSpawnChildActorOnAppropriatePath() throws {
        let probeForTest: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe()

        let parent: ActorRef<ParentProtocol> = try system.spawn(
            "parent",
            self.parentBehavior(
                probe: probeForTest.ref
            )
        )
        parent.tell(
            .spawnChild(
                name: "kid",
                behavior: self.childBehavior(
                    probe: probeForTest.ref
                )
            )
        )

        guard case .spawned(let child) = try probeForTest.expectMessage() else { throw probeForTest.error() }

        let unknownName: String = "capybara"
        parent.tell(.findByName(name: unknownName))
        try probeForTest.expectMessage(.childNotFound(name: unknownName))

        parent.tell(.findByName(name: child.id.name))
        try probeForTest.expectMessage(
            .childFound(
                name: child.id.name,
                ref: child
            )
        )  // should return same (or equal) ref

        parent.tell(.stopByName(name: child.id.name))  // stopping by name
        try probeForTest.expectMessage(
            .childFound(
                name: child.id.name,
                ref: child
            )
        )  // we get the same, now dead, ref back

        probeForTest.watch(child)  // watching dead ref triggers terminated
        try probeForTest.expectTerminated(child)

        parent.tell(.findByName(name: child.id.name))  // should not find that child anymore, it was stopped
        try probeForTest.expectMessage(.childNotFound(name: child.id.name))
    }

    internal func test_contextSpawnAnonymous_shouldSpawnChildActorOnAppropriatePath() throws {
        let probeForTest: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe()

        let parent: ActorRef<ParentProtocol> = try system.spawn(
            "parent",
            self.parentBehavior(
                probe: probeForTest.ref
            )
        )
        parent.tell(
            .spawnAnonymousChild(
                behavior: self.childBehavior(
                    probe: probeForTest.ref
                )
            )
        )

        guard case .spawned(let child) = try probeForTest.expectMessage() else { throw probeForTest.error() }

        parent.tell(.findByName(name: child.id.name))
        try probeForTest.expectMessage(
            .childFound(
                name: child.id.name,
                ref: child
            )
        )  // should return same (or equal) ref

        parent.tell(.stopByName(name: child.id.name))  // stopping by name
        try probeForTest.expectMessage(
            .childFound(
                name: child.id.name,
                ref: child
            )
        )  // we get the same, now dead, ref back

        probeForTest.watch(child)  // watching dead ref triggers terminated
        try probeForTest.expectTerminated(child)

        parent.tell(.findByName(name: child.id.name))  // should not find that child anymore, it was stopped
        try probeForTest.expectMessage(.childNotFound(name: child.id.name))
    }

}
