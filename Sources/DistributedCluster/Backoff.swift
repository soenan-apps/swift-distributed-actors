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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Backoff Strategy protocol

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Backoff Strategy implementations

/// A `BackoffStrategy` abstracts over logic which computes appropriate time amounts to back off at, for a specific
/// call.
///
/// Create instances using `Backoff`, e.g. `Backoff.exponential(...)`, or implement custom strategies by conforming to
/// this protocol.
///
/// See also: `ConstantBackoffStrategy`, `ExponentialBackoffStrategy`
public protocol BackoffStrategy {
    /// Returns next backoff interval to use OR `nil` if no further retries should be performed.
    mutating func next() -> Duration?

    /// Reset the strategy to its initial backoff amount.
    mutating func reset()
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Constant backoff strategy

/// Simple strategy, always yielding the same backoff interval.
///
/// - SeeAlso: `ExponentialBackoffStrategy` for a most commonly used exponentially-increasing strategy
///
/// - SeeAlso: Also used to configure `SupervisionStrategy`.
public struct ConstantBackoffStrategy: BackoffStrategy {
    /// The constant time amount to back-off by each time.
    internal let duration: Duration

    /// 常に同じ待機時間を返す。
    public init(duration: Duration) {
        self.duration = duration
    }

    /// 設定した一定の待機時間を返す。
    public func next() -> Duration? {
        self.duration
    }

    /// 状態を持たないため、次回の待機時間も変わらない。
    public func reset() {
        // durationだけで次の値が決まる。
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Exponential backoff strategy

/// Backoff strategy exponentially yielding greater time amounts each time when triggered.
///
/// Subsequent `next()` invocations cause the base interval amount to grow exponentially (as powers of two).
///
/// Additional random "noise" is applied to the backoff value, in order to avoid multiple actors or nodes re-trying
/// at the same exact rate. The effective backoff time amount is calculated as current base interval multiplied by a
/// random
/// value within the range: `(1 - randomFactor)...(1 + randomFactor)`. Meaning that the actual backoff value will
/// "oscillate"
/// around the expected backoff base, but ever so slightly different each time it is calculated, allowing multiple
/// actors or nodes
/// to attempt retries without causing as much of a tendering heard effect upon the (possibly shared) target resource.
///
/// Example backoff values for `.exponential(initialInterval: .milliseconds(100), randomFactor: 0.25)`:
///
/// | Attempt | multiplier | randomFact |  (base) | (randomized range) |
/// | ------- | ---------- | ---------- | ------- | ------------------ |
/// |       1 |        1.5 |       0.25 |   100ms |   75ms ... 125ms  |
/// |       2 |        1.5 |       0.25 |   150ms | ~127ms ... ~188ms  |
/// |       3 |        1.5 |       0.25 |   225ms | ~191ms ... ~281ms  |
/// |       4 |        1.5 |       0.25 |  ~338ms | ~287ms ... ~422ms  |
/// |       5 |        1.5 |       0.25 |  ~506ms | ~680ms ... ~633ms  |
/// |     ... |        ... |        ... |     ... |        ... |
///
/// Additionally the `maxInterval` can be used to _cap_ the backoff time amount.
/// Note that the backoff will continue yielding the `maxInterval` infinitely times if it has been exceeded,
/// and other means of preventing infinite retries should be applied.
///
/// By changing the `multiplier` it is possible to control the rate at which backoff intervals grow over subsequent
/// attempts.
/// The default value of `1.5` results in a 50% growth of for each `next()` call. Applications wanting to double the
/// backoff
/// interval upon each attempt may set the `multiplier` would be set to `2.0`. Higher multiplier values are also
/// accepted,
/// but not frequently used.
///
/// - SeeAlso: `ConstantBackoffStrategy` for a simple constant backoff strategy.
///
/// - SeeAlso: Also used to configure `SupervisionStrategy`.
public struct ExponentialBackoffStrategy: BackoffStrategy {
    /// Default values for the backoff parameters.
    public enum Defaults {
        /// 最初の基本待機時間。
        public static let initialInterval: Duration = .milliseconds(200)
        /// 基本待機時間に掛ける倍率。
        public static let multiplier: Double = 1.5
        /// 基本待機時間の上限。
        public static let capInterval: Duration = .effectivelyInfinite
        /// 基本待機時間に加える乱数の幅。
        public static let randomFactor: Double = 0.25

        // We could also implement taking a Clock, and using it see if there's a total limit exceeded
        // public static let maxElapsedTime: Duration = .minutes(30)

        /// nilの場合は試行回数を制限しない。
        public static let maxAttempts: Int? = nil
    }

    internal let initialInterval: Duration
    internal let multiplier: Double
    internal let capInterval: Duration
    internal let randomFactor: Double

    internal var limitedRemainingAttempts: Int?

    // interval that will be used in the `next()` call, does NOT include the random noise component
    private var currentBaseInterval: Duration

    internal init(
        initialInterval: Duration,
        multiplier: Double,
        capInterval: Duration,
        randomFactor: Double,
        maxAttempts: Int?
    ) {
        precondition(
            initialInterval.nanoseconds > 0,
            "initialInterval MUST be > 0ns, was: [\(initialInterval.prettyDescription)]"
        )
        precondition(multiplier >= 1.0, "multiplier MUST be >= 1.0, was: [\(multiplier)]")
        precondition(initialInterval <= capInterval, "capInterval MUST be >= initialInterval, was: [\(capInterval)]")
        precondition(
            randomFactor >= 0.0 && randomFactor <= 1.0,
            "randomFactor MUST be within between 0 and 1, was: [\(randomFactor)]"
        )
        if let attempts = maxAttempts {
            precondition(attempts > 0, "maxAttempts MUST be nil or > 0, was: [\(attempts)]")
        }

        self.initialInterval = initialInterval
        self.currentBaseInterval = initialInterval
        self.multiplier = multiplier
        self.capInterval = capInterval
        self.randomFactor = randomFactor
        self.limitedRemainingAttempts = maxAttempts
    }

    /// 残り回数を消費し、乱数を含めた次の待機時間を返す。
    public mutating func next() -> Duration? {
        defer { self.limitedRemainingAttempts? -= 1 }
        if let remainingAttempts = self.limitedRemainingAttempts, remainingAttempts <= 0 {
            return nil
        }  // else, still attempts remaining, or no limit set

        let baseInterval: Duration = self.currentBaseInterval
        let randomizeMultiplier: Double = Double.random(in: (1 - self.randomFactor)...(1 + self.randomFactor))

        if baseInterval > self.capInterval {
            return self.capInterval * randomizeMultiplier
        }
        let randomizedInterval: Duration = baseInterval * randomizeMultiplier
        // potentially logic to check clock if we exceeded total backoff timeout here (and then return nil)
        self.prepareNextInterval()
        return randomizedInterval
    }

    /// Runs `operation` with the configured backoff, throwing the last failure when attempts run out.
    ///
    /// - Parameters:
    ///   - operation: The operation to run, potentially multiple times until successful or maxAttempts were made
    /// - Throws: the last error thrown by `operation`
    public func attempt<Value>(_ operation: () async throws -> Value) async throws -> Value {
        var backoff: Self = self

        do {
            return try await operation()
        } catch {
            var lastError: any Error = error

            while let backoffDuration = backoff.next() {
                try await Task.sleep(for: backoffDuration)
                do {
                    return try await operation()
                } catch {
                    lastError = error
                    // and try again, if remaining tries are left...
                }
            }
            throw lastError
        }
    }

    private mutating func prepareNextInterval() {
        // overflow protection
        if self.currentBaseInterval >= (self.capInterval / self.multiplier) {
            self.currentBaseInterval = self.capInterval
        } else {
            // Duration's compound operator accepts Int, not this Double multiplier.
            // swiftlint:disable:next shorthand_operator
            self.currentBaseInterval = self.currentBaseInterval * self.multiplier
        }
    }

    /// 基本待機時間を初期値に戻す。残り試行回数は変更しない。
    public mutating func reset() {
        self.currentBaseInterval = self.initialInterval
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Errors

internal enum BackoffError {
    case exceededNumberOfAttempts(limit: Int, period: Duration)
}

/// Factory for `BackoffStrategy` instances.
///
/// - SeeAlso: `BackoffStrategy` for interface semantics.
/// - SeeAlso: `ConstantBackoffStrategy` for a simple constant backoff strategy.
/// - SeeAlso: `ExponentialBackoffStrategy` for a most commonly used exponentially-increasing strategy.
///
/// - SeeAlso: Also used to configure `SupervisionStrategy`.
public enum Backoff {
    // implement noLongerThan: .seconds(30), where total time is taken from actor system clock

    /// Backoff each time using the same, constant, time amount.
    ///
    /// See `ConstantBackoffStrategy` for details
    public static func constant(_ backoff: Duration) -> ConstantBackoffStrategy {
        .init(duration: backoff)
    }

    /// Creates a strategy implementing the exponential backoff pattern.
    ///
    /// See `ExponentialBackoffStrategy` for details.
    ///
    /// - Parameters:
    ///   - initialInterval: interval to use as base of all further backoffs,
    ///         usually also the value used for the first backoff.
    ///         MUST be `> 0`.
    ///   - multiplier: multiplier to be applied on each subsequent backoff to the previous backoff interval.
    ///         For example, a value of 1.5 means that each backoff will increase 50% over the previous value.
    ///         MUST be `>= 0`.
    ///   - capInterval: interval limit, beyond which intervals should be truncated to this value.
    ///         MUST be `>= initialInterval`.
    ///   - randomFactor: `0.5` randomizes backoff between 50% below and 50% above the base interval.
    ///         MUST be between: `<0; 1>` (inclusive)
    ///   - maxAttempts: An optional maximum number of times backoffs shall be attempted.
    ///         MUST be `> 0` if set (or `nil`).
    public static func exponential(
        initialInterval: Duration = ExponentialBackoffStrategy.Defaults.initialInterval,
        multiplier: Double = ExponentialBackoffStrategy.Defaults.multiplier,
        capInterval: Duration = ExponentialBackoffStrategy.Defaults.capInterval,
        randomFactor: Double = ExponentialBackoffStrategy.Defaults.randomFactor,
        maxAttempts: Int? = ExponentialBackoffStrategy.Defaults.maxAttempts
    ) -> ExponentialBackoffStrategy {
        .init(
            initialInterval: initialInterval,
            multiplier: multiplier,
            capInterval: capInterval,
            randomFactor: randomFactor,
            maxAttempts: maxAttempts
        )
    }
}
