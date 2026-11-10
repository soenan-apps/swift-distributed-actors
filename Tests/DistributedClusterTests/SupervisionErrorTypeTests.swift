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
import NIO
import XCTest

@testable import DistributedCluster

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

internal final class SupervisionErrorTypeTests: SupervisionTestCase {
    private func throwerBehavior(probe: ActorTestProbe<PleaseReplyError>) -> Behavior<NonTransportableAnyError> {
        .receiveMessage { errorEnvelope in
            switch errorEnvelope.failure {
            case let reply as PleaseReplyError:
                probe.tell(reply)

            case let failure:
                throw failure
            }
            return .same
        }
    }

    internal func testSupervisorShouldOnlyHandleThrowsOfSpecifiedErrorType() throws {
        let probeForTest: ActorTestProbe<PleaseReplyError> = self.testKit.makeTestProbe(
            expecting: PleaseReplyError.self
        )

        let supervisedThrower: ActorRef<NonTransportableAnyError> = try system.spawn(
            "thrower-1",
            self.throwerBehavior(probe: probeForTest),
            props: .supervision(strategy: .restart(atMost: 10, within: nil), forErrorType: EasilyCatchableError.self)
        )

        supervisedThrower.tell(.init(PleaseReplyError()))
        try probeForTest.expectMessage(PleaseReplyError())

        supervisedThrower.tell(.init(EasilyCatchableError()))  // will cause restart
        supervisedThrower.tell(.init(PleaseReplyError()))
        try probeForTest.expectMessage(PleaseReplyError())

        supervisedThrower.tell(.init(CatchMeError()))  // will NOT be supervised

        supervisedThrower.tell(.init(PleaseReplyError()))
        try probeForTest.expectNoMessage(for: .milliseconds(50))
    }

    internal func testSupervisorShouldOnlyHandleAnyThrows() throws {
        let probeForTest: ActorTestProbe<PleaseReplyError> = self.testKit.makeTestProbe(
            expecting: PleaseReplyError.self
        )

        let supervisedThrower: ActorRef<NonTransportableAnyError> = try system.spawn(
            "thrower-2",
            self.throwerBehavior(probe: probeForTest),
            props: .supervision(strategy: .restart(atMost: 100, within: nil), forAll: .errors)
        )

        supervisedThrower.tell(.init(PleaseReplyError()))
        try probeForTest.expectMessage(PleaseReplyError())

        supervisedThrower.tell(.init(EasilyCatchableError()))  // will cause restart
        supervisedThrower.tell(.init(PleaseReplyError()))
        try probeForTest.expectMessage(PleaseReplyError())

        supervisedThrower.tell(.init(CatchMeError()))  // will cause restart

        supervisedThrower.tell(.init(PleaseReplyError()))
        try probeForTest.expectMessage(PleaseReplyError())
    }

    internal func testCompositeSupervisorShouldHandleUsingTheRightHandler() throws {
        let probe: ActorTestProbe<WorkerMessages> = self.testKit.makeTestProbe(expecting: WorkerMessages.self)

        let faultyWorker: ActorRef<FaultyMessage> = try system.spawn(
            "compositeFailures-1",
            self.faulty(probe: probe.ref),
            props: Props()
                .supervision(strategy: .restart(atMost: 1, within: nil), forErrorType: CatchMeError.self)
                .supervision(strategy: .restart(atMost: 1, within: nil), forErrorType: EasilyCatchableError.self)
        )

        probe.watch(faultyWorker)

        faultyWorker.tell(.pleaseThrow(error: CatchMeError()))
        try probe.expectNoTerminationSignal(for: .milliseconds(20))
        faultyWorker.tell(.pleaseThrow(error: EasilyCatchableError()))
        try probe.expectNoTerminationSignal(for: .milliseconds(20))
        faultyWorker.tell(.pleaseThrow(error: CantTouchThisError()))
        try probe.expectTerminated(faultyWorker)
    }
}
