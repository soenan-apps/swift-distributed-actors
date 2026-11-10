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
    internal func test_contextSpawn_duplicateNameShouldFail() throws {
        let probeForTest: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe()

        let parent: ActorRef<ParentProtocol> = try system.spawn(
            "parent-2",
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

        _ = try probeForTest.expectMessageMatching { value -> ActorRef<ChildProtocol>? in
            switch value {
            case .spawned(let child):
                return child

            default:
                return nil
            }
        }

        parent.tell(
            .spawnChild(
                name: "kid",
                behavior: self.childBehavior(
                    probe: probeForTest.ref
                )
            )
        )

        _ = try probeForTest.expectMessageMatching { value -> ActorPath? in
            switch value {
            case .spawnFailed(let path):
                return path

            default:
                return nil
            }
        }
    }

    internal func test_contextStop_shouldStopChild() throws {
        let probeForTest: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe()

        let parent: ActorRef<ParentProtocol> = try system.spawn(
            "parent-3",
            self.parentBehavior(
                probe: probeForTest.ref,
                notifyWhenChildStops: true
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

        guard case .spawned = try probeForTest.expectMessage() else { throw probeForTest.error() }

        parent.tell(.stopByName(name: "kid"))

        _ = try probeForTest.expectMessageMatching { value -> String? in
            switch value {
            case .childFound(name: "kid", _):
                return name

            default:
                return nil
            }
        }

        try probeForTest.expectMessage(.childStopped(name: "kid"))
    }

    internal func test_contextStop_shouldThrowIfRefIsNotChild() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let parent: ActorRef<String> = try system.spawn(
            "parent-4",

            .receive { context, _ in
                do {
                    try context.stop(child: probeForTest.ref)
                } catch {
                    probeForTest.tell("Errored:\(error)")
                    throw error  // throw as if we did not catch it
                }
                return .same
            }
        )

        probeForTest.watch(parent)

        parent.tell("stop")

        try probeForTest.expectMessage().shouldStartWith(
            prefix: """
                Errored:ActorContextError(attemptedStoppingNonChildActor(ref: \
                AddressableActorRef(/user/$testProbe
                """
        )
        try probeForTest.expectTerminated(parent)
    }

    internal func test_contextStop_shouldThrowIfRefIsMyself() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let parent: ActorRef<String> = try system.spawn(
            "parent-5",

            .receive { context, _ in
                do {
                    try context.stop(child: context.myself)
                } catch {
                    probeForTest.tell("Errored:\(error)")
                    throw error  // throw as if we did not catch it
                }
                return .same
            }
        )

        probeForTest.watch(parent)

        parent.tell("stop")

        try probeForTest.expectMessage().shouldStartWith(
            prefix: """
                Errored:ActorContextError(attemptedStoppingMyselfUsingContext(ref: \
                AddressableActorRef(/user/parent-5
                """
        )
        try probeForTest.expectTerminated(parent)
    }

    internal func test_spawnStopSpawn_shouldWorkWithSameChildName() throws {
        let probeForTest: ActorTestProbe<Never> = self.testKit.makeTestProbe("p")
        let firstProbe: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe("p1")
        let secondProbe: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe("p2")

        let parent: ActorRef<String> = try system.spawn(
            .anonymous,

            .receive { context, msg in
                switch msg {
                case "spawn":
                    let refA: ActorRef<ChildProtocol> = try context.spawn(
                        "child",

                        .setup { context in
                            firstProbe.tell(.spawned(child: context.myself))
                            return .ignore
                        }
                    )
                    try context.stop(child: refA)

                    let refB: ActorRef<ChildProtocol> = try context.spawn(
                        "child",

                        .setup { context in
                            secondProbe.tell(.spawned(child: context.myself))
                            return .ignore
                        }
                    )
                    try context.stop(child: refB)

                    return .same

                default:
                    return .ignore
                }
            }
        )

        probeForTest.watch(parent)
        parent.tell("spawn")

        // would be useful to provide some expectSpawned since it's such a common thing
        guard case .spawned(let childA) = try firstProbe.expectMessage() else { throw firstProbe.error() }
        firstProbe.watch(childA)
        guard case .spawned(let childB) = try secondProbe.expectMessage() else { throw secondProbe.error() }
        secondProbe.watch(childB)

        try firstProbe.expectTerminated(childA, within: .milliseconds(500))
        try secondProbe.expectTerminated(childB, within: .milliseconds(500))
        try probeForTest.expectNoTerminationSignal(for: .milliseconds(100))
    }

    internal func test_throwOfSpawnedChild_shouldNotCauseParentToTerminate() throws {
        let probeForTest: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe()

        let childBehavior: Behavior<ChildProtocol> = self.childBehavior(
            probe: probeForTest.ref
        )

        let parentBehavior: Behavior<String> = Behavior<String>.receive { context, msg in
            switch msg {
            case "spawn":
                let childRef: ActorRef<ChildProtocol> = try context.spawn("child", childBehavior)
                probeForTest.tell(.spawned(child: childRef))
                return .same

            default:
                return .ignore
            }
        }

        let parent: ActorRef<String> = try system.spawn("watchingParent", parentBehavior)

        probeForTest.watch(parent)
        parent.tell("spawn")

        guard case .spawned(let child) = try probeForTest.expectMessage() else { throw probeForTest.error() }
        probeForTest.watch(child)

        child.tell(.throwWhoops)

        // since the parent watched the child, it will also terminate
        try probeForTest.expectTerminated(child)
        try probeForTest.expectNoTerminationSignal(for: .milliseconds(200))

        // yet it MUST allow spawning another child with the same name now, since the previous one has terminated
        parent.tell("spawn")

        let secondChild: ActorRef<ChildProtocol> = try probeForTest.expectMessageMatching { closureArgument in
            guard case .spawned(let ref) = closureArgument else {
                return nil
            }
            return probeForTest.watch(ref)
        }

        secondChild.id.path.shouldEqual(child.id.path)
        secondChild.id.incarnation.shouldNotEqual(child.id.incarnation)
    }

    internal func test_throwOfWatchedSpawnedChild_shouldCauseParentToTerminate() throws {
        let probeForTest: ActorTestProbe<ParentChildProbeProtocol> = self.testKit.makeTestProbe()

        let stoppingChildBehavior: Behavior<ChildProtocol> = self.childBehavior(
            probe: probeForTest.ref
        )

        let parentBehavior: Behavior<String> = Behavior<String>.receive { context, msg in
            switch msg {
            case "spawn":
                let childRef: ActorRef<ChildProtocol> = try context.spawnWatch("child", stoppingChildBehavior)
                probeForTest.tell(.spawned(child: childRef))
                return .same

            default:
                return .ignore
            }
        }

        let parent: ActorRef<String> = try system.spawn("watchingParent", parentBehavior)

        probeForTest.watch(parent)
        parent.tell("spawn")

        guard case .spawned(let child) = try probeForTest.expectMessage() else { throw probeForTest.error() }
        probeForTest.watch(child)

        child.tell(.throwWhoops)

        // since the parent watched the child, it will also terminate
        try probeForTest.expectTerminatedInAnyOrder([child.asAddressable, parent.asAddressable])
    }
}
