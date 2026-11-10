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

// There are a few ways we could go about implementing this, we currently do a simple scan for "first one that handles",
// which should be quite good enough esp. since we expect the supervisors to be usually not more than just a few.
//
// The scan also makes implementing the "catch" all types `Supervision.AllFailures` etc simpler rather than having
// to search
// the underlying map for the catch all handlers as well as the specific error.
internal final class CompositeSupervisor<Message: Codable>: Supervisor<Message> {
    private let supervisors: [Supervisor<Message>]

    internal init(supervisors: [Supervisor<Message>]) {
        assert(supervisors.count > 1, """
            There is no need to use a composite supervisor if only one supervisor is passed in. \
            Consider this a Swift Distributed Actors bug.
            """)
        self.supervisors = supervisors
        super.init()
    }

    override internal func handleFailure(
        _ context: ActorContext<Message>,
        target: Behavior<Message>,
        failure: Supervision.Failure,
        processingType: ProcessingType
    ) throws -> SupervisionDirective<Message> {
        for supervisor in self.supervisors where supervisor.canHandle(failure: failure) {

            return try supervisor.handleFailure(
                context, target: target, failure: failure, processingType: processingType
            )

        }
        return .stop
    }

    override internal func canHandle(failure: Supervision.Failure) -> Bool {
        self.supervisors.contains { supervisor in
            supervisor.canHandle(failure: failure)
        }
    }
}
