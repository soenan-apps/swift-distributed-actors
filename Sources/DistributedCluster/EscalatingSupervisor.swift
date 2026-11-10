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

/// Escalates failure to parent, while failing the current actor.
internal final class EscalatingSupervisor<Message: Codable>: Supervisor<Message> {
    internal let failureType: Error.Type
    override internal var descriptionForLogs: String {
        "[.escalate<\(self.failureType)>] supervision strategy"
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
            return .escalate(failure)
        }
        return .stop
    }

    override internal func isSame(as other: Supervisor<Message>) -> Bool {
        if let escalatingSupervisor = other as? EscalatingSupervisor<Message> {
            return self.failureType == escalatingSupervisor.failureType
        }
        return false
    }

    override internal func canHandle(failure: Supervision.Failure) -> Bool {
        failure.shouldBeHandled(bySupervisorHandling: self.failureType)
    }
}
