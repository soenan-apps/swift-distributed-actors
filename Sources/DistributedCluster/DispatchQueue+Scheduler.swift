// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

import Dispatch

extension DispatchQueue: Scheduler {
    internal func scheduleOnce(delay: Duration, _ operation: @escaping () -> Void) -> Cancelable {
        let workItem: DispatchWorkItem = DispatchWorkItem(block: operation)
        self.asyncAfter(deadline: .init(nowDelayedBy: delay), execute: workItem)
        return workItem
    }

    internal func scheduleOnceAsync(
        delay: Duration,
        _ operation: @Sendable @escaping () async -> Void
    ) -> Cancelable {
        let workItem: DispatchWorkItem = DispatchWorkItem { () in
            Task {
                await operation()
            }
        }
        self.asyncAfter(deadline: .init(nowDelayedBy: delay), execute: workItem)
        return workItem
    }

    internal func scheduleOnce<Message>(
        delay: Duration,
        receiver: ActorRef<Message>,
        message: Message
    ) -> Cancelable {
        self.scheduleOnce(delay: delay) {
            receiver.tell(message)
        }
    }

    internal func schedule(
        initialDelay: Duration,
        interval: Duration,
        _ operation: @Sendable @escaping () -> Void
    ) -> Cancelable {
        let cancellable: FlagCancelable = FlagCancelable()

        @Sendable
        func sched() {
            if !cancellable.isCanceled {
                let nextDeadline: DispatchTime = DispatchTime(nowDelayedBy: interval)
                operation()
                self.asyncAfter(deadline: nextDeadline, execute: sched)
            }
        }

        self.asyncAfter(deadline: .init(nowDelayedBy: initialDelay), execute: sched)

        return cancellable
    }

    internal func scheduleAsync(
        initialDelay: Duration,
        interval: Duration,
        _ operation: @Sendable @escaping () async -> Void
    ) -> Cancelable {
        let cancellable: FlagCancelable = FlagCancelable()

        @Sendable
        func sched() {
            if !cancellable.isCanceled {
                let nextDeadline: DispatchTime = DispatchTime(nowDelayedBy: interval)
                Task {
                    await operation()
                    self.asyncAfter(deadline: nextDeadline, execute: sched)
                }
            }
        }

        self.asyncAfter(deadline: .init(nowDelayedBy: initialDelay), execute: sched)

        return cancellable
    }

    internal func schedule<Message>(
        initialDelay: Duration,
        interval: Duration,
        receiver: ActorRef<Message>,
        message: Message
    ) -> Cancelable {
        self.schedule(initialDelay: initialDelay, interval: interval) {
            receiver.tell(message)
        }
    }
}
