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

/// Instructs the mailbox to take specific action, reflecting wha the supervisor intends to do with the actor.
///
/// - SeeAlso: `Supervisor.handleFailure`
internal enum SupervisionDirective<Message: Codable> {
    /// Directs the mailbox to immediately fail and stop processing.
    /// Failures should "bubble up".
    case escalate(Supervision.Failure)
    /// Directs mailbox to prepare a restart after a delay.
    case restartDelayed(Duration, Behavior<Message>)
    /// Directs mailbox to prepare AND complete a restart immediately.
    case restartImmediately(Behavior<Message>)
    /// Directs mailbox to directly stop processing.
    case stop
}
