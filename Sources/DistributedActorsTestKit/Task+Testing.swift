// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

extension Task {
    /// Records the start and elapsed time of a testing timeout.
    public struct SimpleTimeoutError<Clock: _Concurrency.Clock>: Error {
        /// The instant at which the timed operation began.
        public let start: Clock.Instant
        /// The time elapsed when the timeout error was created.
        public let elapsed: Clock.Duration

        /// Captures elapsed time from the supplied clock.
        public init(clock: Clock, start: Clock.Instant) {
            self.start = start
            self.elapsed = start.duration(to: clock.now)
        }
    }

    internal static func cancelAfter(
        timeout: Duration,
        timeoutError: @escaping @autoclosure @Sendable () -> Error,
        body: @escaping @Sendable () async throws -> Success
    ) -> Task<Success, any Error> {
        Self.cancelAfter(timeout: timeout, timeoutError: { _, _ in timeoutError() }, body: body)
    }

    /// Races a testing body against a timeout, cancelling and joining the remaining task.
    internal static func cancelAfter(
        timeout: Duration,
        timeoutError _: @Sendable (ContinuousClock.Instant, ContinuousClock.Duration) -> Error,
        body: @escaping @Sendable () async throws -> Success
    ) -> Task<Success, any Error> {
        let start: ContinuousClock.Instant = ContinuousClock.now
        return Task<Success, Error> {
            try await withThrowingTaskGroup(of: Success.self) { group in
                group.addTask {
                    try await body()
                }

                group.addTask(priority: .high) {
                    try? await Task<Never, Never>.sleep(until: start + timeout, clock: .continuous)
                    throw SimpleTimeoutError(clock: .continuous, start: start)
                }

                defer {
                    group.cancelAll()
                }
                guard let result = try await group.next() else {
                    preconditionFailure("The timeout race always contains two tasks")
                }
                return result
            }
        }
    }

}
