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

extension ParentChildActorTests {
    internal func test_watchedChild_shouldProduceInSingleTerminatedSignal() throws {
        let probeForTest: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe()
        let pChild: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let childBehavior: Behavior<ChildProtocol> = self.childBehavior(
            probe: probeForTest.ref
        )

        let parentBehavior: Behavior<String> = Behavior<String>.receive { context, msg in
            switch msg {
            case "spawn":
                let childRef: ActorRef<ChildProtocol> = try context.spawnWatch("child", childBehavior)
                probeForTest.tell(.spawned(child: childRef))
                return .same

            default:
                return .ignore
            }
        }.receiveSignal { _, signal in
            switch signal {
            case let terminated as Signals.ChildTerminated:
                // only this should match
                probeForTest.tell(.childStopped(name: "child-term:\(terminated.id.name)"))

            case let terminated as Signals.Terminated:
                // no second "generic" terminated should be sent (though one could match for just Terminated)
                probeForTest.tell(.childStopped(name: "term:\(terminated.id.name)"))

            default:
                return .ignore
            }
            return .same
        }

        let parent: ActorRef<String> = try system.spawn("watchingParent", parentBehavior)

        probeForTest.watch(parent)
        parent.tell("spawn")

        guard case .spawned(let child) = try probeForTest.expectMessage() else { throw probeForTest.error() }
        probeForTest.watch(child)

        child.tell(.howAreYou(replyTo: pChild.ref))
        // Give the parent time to watch the child, rather than its dead cell.
        _ = try pChild.expectMessage()

        child.tell(.throwWhoops)

        // since the parent watched the child, it will also terminate
        try probeForTest.expectTerminated(child)
        switch try probeForTest.expectMessage() {
        case .childStopped(let name):
            name.shouldEqual("child-term:child")

        default:
            throw probeForTest.error()
        }
        try probeForTest.expectNoMessage(for: .milliseconds(100))  // no second terminated should happen
    }

    internal func test_spawnWatch_shouldSpawnAWatchedActor() throws {
        let probeForTest: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe()

        let parentBehavior: Behavior<String> = .receive { context, message in
            switch message {
            case "spawn":
                let childRef: ChildRef = try context.spawnWatch("child", .stop)
                probeForTest.tell(.spawned(child: childRef))

            default:
                ()
            }
            return .same
        }

        let parent: ActorRef<String> = try system.spawn(
            .anonymous,

            parentBehavior.receiveSignal { _, signal in
                if case let terminated as Signals.Terminated = signal {
                    probeForTest.tell(.childStopped(name: terminated.id.name))
                }

                return .same
            }
        )

        parent.tell("spawn")

        guard case .spawned(let childRef) = try probeForTest.expectMessage() else { throw probeForTest.error() }
        guard case .childStopped(let name) = try probeForTest.expectMessage() else { throw probeForTest.error() }

        childRef.id.name.shouldEqual(name)
    }

    internal func test_stopParent_shouldWaitForChildrenToStop() throws {
        let probeForTest: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe()

        let parent: ActorRef<ParentProtocol> = try system.spawn(
            "parent",
            self.parentBehavior(
                probe: probeForTest.ref
            )
        )
        parent.tell(
            .spawnChild(
                name: "child",
                behavior: self.childBehavior(
                    probe: probeForTest.ref
                )
            )
        )
        probeForTest.watch(parent)

        guard case .spawned(let childRef) = try probeForTest.expectMessage() else { throw probeForTest.error() }
        probeForTest.watch(childRef)

        childRef.tell(
            .makeChild(
                name: "grandChild",
                behavior: self.childBehavior(
                    probe: probeForTest.ref
                )
            )
        )

        guard case .spawned(let grandchildRef) = try probeForTest.expectMessage() else { throw probeForTest.error() }
        probeForTest.watch(grandchildRef)

        parent.tell(.stop)

        try probeForTest.expectTerminatedInAnyOrder(
            [
                parent.asAddressable, childRef.asAddressable,
                grandchildRef.asAddressable,
            ]
        )
    }

    internal func test_spawnStopSpawnManyTimesWithSameName_shouldProperlyTerminateAllChildren() throws {
        let probeForTest: ActorTestProbe<Int> = self.testKit.makeTestProbe("p")
        let childCount: Int = 100

        let parent: ActorRef<String> = try system.spawn(
            .anonymous,

            .receive { context, msg in
                switch msg {
                case "spawn":
                    for count in 1...childCount {
                        let behavior: Behavior<Int> = .receiveMessage { _ in .ignore }
                        let ref: ActorRef<Int> = try context.spawn(
                            "child",

                            behavior.receiveSignal { _, signal in
                                if signal is Signals.PostStop {
                                    probeForTest.tell(count)
                                }

                                return .same
                            }
                        )
                        try context.stop(child: ref)
                    }

                    return .same

                default:
                    return .ignore
                }
            }
        )

        parent.tell("spawn")

        let messages: [Int] = try probeForTest.expectMessages(count: childCount)
        messages.sorted().shouldEqual((1...childCount).sorted())
    }
}
