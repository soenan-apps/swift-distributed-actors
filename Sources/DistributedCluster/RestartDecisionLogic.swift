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

/// Encapsulates logic around when a restart is allowed, i.e. tracks the deadlines of failure periods.
internal struct RestartDecisionLogic {
    internal let maxRestarts: Int
    internal let within: Duration?
    internal var backoffStrategy: BackoffStrategy?

    // counts how many times we failed during the "current" `within` period
    private var restartsWithinCurrentPeriod: Int = 0
    private var restartsPeriodDeadline: ContinuousClock.Instant = .distantPast
    private var periodHasTimeLeft: Bool {
        self.restartsPeriodDeadline.hasTimeLeft(until: .now)
    }

    private var isWithinMaxRestarts: Bool {
        self.restartsWithinCurrentPeriod <= self.maxRestarts
    }

    /// Human readable description of how the status of the restart supervision strategy
    internal var remainingRestartsDescription: String {
        var description: String = "\(self.restartsWithinCurrentPeriod) of \(self.maxRestarts) max restarts consumed"
        if let within = self.within {
            description += ", within: \(within.prettyDescription)"
        }
        return description
    }

    internal init(maxRestarts: Int, within: Duration?, backoffStrategy: BackoffStrategy?) {
        precondition(maxRestarts > 0, "RestartStrategy.maxRestarts MUST be > 0")
        self.maxRestarts = maxRestarts
        if let failurePeriodTime = within {
            precondition(
                failurePeriodTime.nanoseconds > 0,
                """
                RestartStrategy.within MUST be > 0. For supervision without time bounds (i.e. \
                absolute count of restarts allowed) use `.restart(:atMost)` instead.
                """
            )
            self.within = failurePeriodTime
        } else {
            // if within was not set, we treat is as if "no time limit", which we mimic by a
            // ContinuousClock.Instant far far away in time
            self.restartsPeriodDeadline = .distantFuture
            self.within = nil
        }
        self.backoffStrategy = backoffStrategy
    }

    /// Increment the failure counter (and possibly reset the failure period deadline).
    ///
    /// MUST be called whenever a failure reaches a supervisor.
    internal mutating func recordFailure() -> SupervisionDecision {
        if self.restartsPeriodDeadline.isOverdue() {
            // thus the next period starts, and we will start counting the failures within that time window anew

            // ! safe, because we are guaranteed to never exceed the .distantFuture deadline that is
            // set when within is nil
            guard let failurePeriodDuration: Duration = self.within else {
                preconditionFailure("An unbounded restart period cannot expire")
            }
            self.restartsPeriodDeadline = .fromNow(failurePeriodDuration)
            self.restartsWithinCurrentPeriod = 0
        }
        self.restartsWithinCurrentPeriod += 1

        if self.periodHasTimeLeft, self.isWithinMaxRestarts {
            guard self.backoffStrategy != nil else {
                return .restartImmediately
            }

            // so the backoff strategy _is_ set, and a `nil` from it would mean "stop restarting"
            if let backoffAmount = self.backoffStrategy?.next() {
                return .restartBackoff(delay: backoffAmount)
            }
            // we stop since the strategy decided we've been trying again enough and it is time to stop

            return .stop

        }
        // e.g. total time within which we are allowed to back off has been exceeded etc

        return .stop
    }
}
