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

/// Supervisor equivalent to not having supervision enabled, since stopping is the default behavior of failing actors.
/// At the same time, it may be useful to sometimes explicitly specify that for some type of error we want to stop
/// (e.g. when used with composite supervisors, which restart for all failures, yet should not do so for some
/// specific type of error).
internal final class StoppingSupervisor<Message: Codable>: Supervisor<Message> {
    internal let failureType: Error.Type
    override internal var descriptionForLogs: String {
        "[.stop] supervision strategy"
    }

    internal init(failureType: Error.Type) {
        self.failureType = failureType
    }

    override internal func handleFailure(
        _: ActorContext<Message>,
        target _: Behavior<Message>,
        failure: Supervision.Failure,
        processingType _: ProcessingType
    ) -> SupervisionDirective<Message> {
        if failure.shouldBeHandled(bySupervisorHandling: self.failureType) {

            return .stop
        }
        return .stop
    }

    override internal func isSame(as other: Supervisor<Message>) -> Bool {
        if let stoppingSupervisor = other as? StoppingSupervisor<Message> {
            return self.failureType == stoppingSupervisor.failureType
        }
        return false
    }

    override internal func canHandle(failure: Supervision.Failure) -> Bool {
        failure.shouldBeHandled(bySupervisorHandling: self.failureType)
    }
}
