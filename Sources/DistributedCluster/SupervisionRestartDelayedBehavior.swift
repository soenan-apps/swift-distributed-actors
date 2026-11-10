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

/// Behavior used to suspend after a `restartPrepare` has been issued by an `restartDelayed`.
@usableFromInline
internal enum SupervisionRestartDelayedBehavior<Message: Codable> {
    @usableFromInline
    internal struct WakeUp {}

    @usableFromInline
    internal static func after(delay: Duration, with replacement: Behavior<Message>) -> Behavior<Message> {
        .setup { context in
            context.timers.startResumeTimer(
                key: TimerKey("restartBackoff", isSystemTimer: true), delay: delay, resumeWith: WakeUp()
            )

            return .suspend { (result: Result<WakeUp, Error>) in
                traceLog_Supervision("RESTART BACKOFF TRIGGER")
                switch result {
                case .failure(let error):
                    context.log.error(
                        "Failed result during backoff restart. Error was: \(error). Forcing actor to crash."
                    )
                    throw error

                case .success:
                    // _downcast safe, we know this may only ever run for a local ref, thus it
                    // will definitely be an ActorCell
                    return try context.downcastUnsafe.restartComplete(with: replacement)
                }
            }
        }
    }
}
