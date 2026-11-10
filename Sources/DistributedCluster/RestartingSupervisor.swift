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

import Logging

internal final class RestartingSupervisor<Message: Codable>: Supervisor<Message>, CustomStringConvertible {
    internal let failureType: Error.Type

    internal let initialBehavior: Behavior<Message>

    private var restartDecider: RestartDecisionLogic
    override internal var descriptionForLogs: String {
        "[.restart(\(self.restartDecider))] supervision strategy"
    }
    internal var description: String {

        """
        RestartingSupervisor(initialBehavior: \(self.initialBehavior), strategy: \
        \(self.restartDecider), canHandle: \(self.failureType))
        """
    }

    internal init(
        initialBehavior behavior: Behavior<Message>,
        restartLogic: RestartDecisionLogic,
        failureType: Error.Type
    ) {
        self.initialBehavior = behavior
        self.restartDecider = restartLogic
        self.failureType = failureType
    }

    override internal func handleFailure(
        _: ActorContext<Message>,
        target _: Behavior<Message>,
        failure: Supervision.Failure,
        processingType: ProcessingType
    ) -> SupervisionDirective<Message> {
        let decision: SupervisionDecision = self.restartDecider.recordFailure()

        guard failure.shouldBeHandled(bySupervisorHandling: self.failureType) else {
            traceLog_Supervision(
                """
                ESCALATE from \(processingType) \
                (\(self.restartDecider.remainingRestartsDescription)), failure was: \
                \(failure)! >>>> \(self.initialBehavior)
                """
            )

            return .stop
        }

        switch decision {
        case .stop:
            traceLog_Supervision(
                """
                STOP from \(processingType) (\(self.restartDecider.remainingRestartsDescription)), \
                failure was: \(failure)! >>>> \(self.initialBehavior)
                """
            )

            return .stop

        case .escalate:
            traceLog_Supervision(
                """
                ESCALATE from \(processingType) \
                (\(self.restartDecider.remainingRestartsDescription)), failure was: \
                \(failure)! >>>> \(self.initialBehavior)
                """
            )

            return .escalate(failure)

        case .restartImmediately:

            traceLog_Supervision(
                """
                RESTART from \(processingType) \
                (\(self.restartDecider.remainingRestartsDescription)), failure was: \
                \(failure)! >>>> \(self.initialBehavior)
                """
            )

            return .restartImmediately(self.initialBehavior)

        case .restartBackoff(let delay):
            traceLog_Supervision(
                """
                RESTART BACKOFF(\(delay.prettyDescription)) from \(processingType) \
                (\(self.restartDecider.remainingRestartsDescription)), failure was: \
                \(failure)! >>>> \(self.initialBehavior)
                """
            )

            return .restartDelayed(delay, self.initialBehavior)
        }
    }

    override internal func canHandle(failure: Supervision.Failure) -> Bool {
        failure.shouldBeHandled(bySupervisorHandling: self.failureType)
    }

    override internal func isSame(as other: Supervisor<Message>) -> Bool {
        other is RestartingSupervisor<Message>
    }
}
