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

import DistributedActorsConcurrencyHelpers
import DistributedActorsTestKit
import Foundation
import NIO
import XCTest

@testable import DistributedCluster

internal final class BehaviorLifecycleTests: SingleClusterSystemXCTestCase {
    internal enum ContextClosureMessage: NotActuallyCodableMessage {
        case context(() -> ActorRef<String>)
    }

    internal func testStoppedWithPostStopShouldTriggerPostStopCallback() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<Never> = .stop { _ in
            probeForTest.tell("postStop")
        }

        try system.spawn(.anonymous, behavior)

        try probeForTest.expectMessage("postStop")
    }

    internal func testStoppedWithPostStopThrowsShouldTerminate() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<Never> = .stop(
            postStop: .signalHandling(handleMessage: .ignore) { _, _ in
                probeForTest.tell("postStop")
                throw TestError("Boom")
            }
        )

        let ref: ActorRef<Never> = try system.spawn(.anonymous, behavior)

        probeForTest.watch(ref)

        try probeForTest.expectMessage("postStop")
        try probeForTest.expectTerminated(ref)
    }

    internal func testMakeAsynchronousCallbackShouldExecuteClosureInActorContext() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .receive { context, msg in
            let callback: AsynchronousCallback<Void> = context.makeAsynchronousCallback {
                // This is a nasty trick to determine that the closure is
                // actually being executed in the context of the actor. After
                // calling the closure, it will check if the actor is still
                // supposed to run and if it's not, it will be stopped.
                context.myself.unsafeUnwrapCell.actor?.behavior = .stop
                probeForTest.tell("fromCallback:\(msg)")
            }

            callback.invoke(())
            return .same
        }

        let ref: ActorRef<String> = try system.spawn(.anonymous, behavior)
        probeForTest.watch(ref)

        ref.tell("test")
        try probeForTest.expectMessage("fromCallback:test")
        try probeForTest.expectTerminated(ref)
    }

    internal func testMyselfShouldStayValidAfterActorStopped() throws {
        let probeForTest: ActorTestProbe<ContextClosureMessage> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .setup { context in
            probeForTest.tell(
                .context {
                    context.myself
                }
            )

            return .stop
        }

        let ref: ActorRef<String> = try system.spawn("myselfStillValidAfterStopped", behavior)
        probeForTest.watch(ref)

        ref.tell("test")  // this does nothing
        try probeForTest.expectTerminated(ref)
        switch try probeForTest.expectMessage() {
        case .context(let closure):
            let closureRef: ActorRef<String> = closure()
            ref.shouldEqual(closureRef)
        }
    }
}
