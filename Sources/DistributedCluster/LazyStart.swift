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

/// Represents an actor that has been initialized, but not yet scheduled to run. Calling `wakeUp` will
/// cause the actor to be scheduled.
///
/// **CAUTION** Not calling `wakeUp` will prevent the actor from ever running
/// and can cause leaks. Also `wakeUp` MUST NOT be called more than once,
/// as that would violate the single-threaded execution guaranteed of actors.
internal struct LazyStart<Message: Codable> {
    internal let ref: ActorRef<Message>

    internal func wakeUp() {
        self.ref.unsafeUnwrapCell.mailbox.schedule()
    }
}
