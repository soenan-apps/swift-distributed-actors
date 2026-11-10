// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

internal protocol Scheduler: Sendable {
    func scheduleOnce(delay: Duration, _ operation: @escaping () -> Void) -> Cancelable
    func scheduleOnceAsync(delay: Duration, _ operation: @Sendable @escaping () async -> Void) -> Cancelable

    func scheduleOnce<Message>(delay: Duration, receiver: ActorRef<Message>, message: Message) -> Cancelable

    func schedule(initialDelay: Duration, interval: Duration, _ operation: @Sendable @escaping () -> Void) -> Cancelable
    func scheduleAsync(
        initialDelay: Duration,
        interval: Duration,
        _ operation: @Sendable @escaping () async -> Void
    ) -> Cancelable

    func schedule<Message>(
        initialDelay: Duration,
        interval: Duration,
        receiver: ActorRef<Message>,
        message: Message
    ) -> Cancelable
}
