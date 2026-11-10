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

import enum Dispatch.DispatchTimeInterval
import struct NIO.TimeAmount

extension Duration {
    internal typealias Value = Int64

    /// Represents number of nanoseconds within given time unit
    internal enum TimeUnit: Value {
        // @formatter:off
        case days = 86_400_000_000_000
        case hours = 3_600_000_000_000
        case microseconds = 1_000
        case milliseconds = 1_000_000
        case minutes = 60_000_000_000
        case nanoseconds = 1
        case seconds = 1_000_000_000
        // @formatter:on

        internal var abbreviated: String {
            switch self {
            case .nanoseconds:
                return "ns"

            case .microseconds:
                return "μs"

            case .milliseconds:
                return "ms"

            case .seconds:
                return "s"

            case .minutes:
                return "m"

            case .hours:
                return "h"

            case .days:
                return "d"
            }
        }

        internal func duration(_ duration: Int) -> Duration {
            switch self {
            case .nanoseconds:
                return .nanoseconds(Value(duration))

            case .microseconds:
                return .microseconds(Value(duration))

            case .milliseconds:
                return .milliseconds(Value(duration))

            case .seconds:
                return .seconds(Value(duration))

            case .minutes:
                return .minutes(Value(duration))

            case .hours:
                return .hours(Value(duration))

            case .days:
                return .hours(Value(duration) * 24)
            }
        }
    }

    /// Largest time amount expressible using this type.
    /// Roughly equivalent to 292 years, which for the intents and purposes of this type can serve as "infinite".
    internal static var effectivelyInfinite: Duration = .nanoseconds(Value.max)

    internal var nanoseconds: Value {
        let (wholeSeconds, attoseconds): (Value, Value) = self.components
        let sNanos: Value = wholeSeconds * Value(1_000_000_000)
        let asNanos: Value = attoseconds / Value(1_000_000_000)
        let (totalNanos, overflow): (Value, Bool) = sNanos.addingReportingOverflow(asNanos)
        return overflow ? .max : totalNanos
    }

    /// The microseconds representation of the `TimeAmount`.
    internal var microseconds: Value {
        self.nanoseconds / TimeUnit.microseconds.rawValue
    }

    /// The milliseconds representation of the `TimeAmount`.
    internal var milliseconds: Value {
        self.nanoseconds / TimeUnit.milliseconds.rawValue
    }

    /// The seconds representation of the `TimeAmount`.
    internal var seconds: Value {
        self.nanoseconds / TimeUnit.seconds.rawValue
    }

    internal var isEffectivelyInfinite: Bool {
        self.nanoseconds == .max
    }

    internal var toNIO: NIO.TimeAmount {
        .nanoseconds(self.nanoseconds)
    }

    /// Creates a new `Duration` for the given amount of minutes.
    ///
    /// - parameters:
    ///     - amount: the amount of minutes this `Duration` represents.
    /// - returns: the `Duration` for the given amount.
    internal static func minutes(_ amount: Value) -> Duration {
        .nanoseconds(amount * 1_000 * 1_000 * 1_000 * 60)
    }

    internal static func minutes(_ amount: Int) -> Duration {
        self.minutes(Value(amount))
    }

    /// Creates a new `Duration` for the given amount of hours.
    ///
    /// - parameters:
    ///     - amount: the amount of hours this `Duration` represents.
    /// - returns: the `Duration` for the given amount.
    internal static func hours(_ amount: Value) -> Duration {
        .nanoseconds(amount * 1_000 * 1_000 * 1_000 * 60 * 60)
    }

    internal static func hours(_ amount: Int) -> Duration {
        self.hours(Value(amount))
    }

    private func chooseUnit(_ nanosecondCount: Value) -> TimeUnit {
        // @formatter:off
        if nanosecondCount / TimeUnit.days.rawValue > 0 {
            return TimeUnit.days
        }
        if nanosecondCount / TimeUnit.hours.rawValue > 0 {
            return TimeUnit.hours
        }
        if nanosecondCount / TimeUnit.minutes.rawValue > 0 {
            return TimeUnit.minutes
        }
        if nanosecondCount / TimeUnit.seconds.rawValue > 0 {
            return TimeUnit.seconds
        }
        if nanosecondCount / TimeUnit.milliseconds.rawValue > 0 {
            return TimeUnit.milliseconds
        }
        if nanosecondCount / TimeUnit.microseconds.rawValue > 0 {
            return TimeUnit.microseconds
        }
        return TimeUnit.nanoseconds
        // @formatter:on
    }
}

extension ContinuousClock.Instant {
    internal static var distantPast: ContinuousClock.Instant {
        .now - Duration.effectivelyInfinite
    }

    internal static var distantFuture: ContinuousClock.Instant {
        .now + Duration.effectivelyInfinite
    }

    internal var timeLeft: Duration {
        self - .now
    }

    internal static func fromNow(_ amount: Duration) -> ContinuousClock.Instant {
        .now + amount
    }

    /// - Returns: true if the deadline is still pending with respect to the passed in `now` time instant
    internal func hasTimeLeft() -> Bool {
        self.hasTimeLeft(until: .now)
    }

    internal func hasTimeLeft(until: ContinuousClock.Instant) -> Bool {
        !self.isBefore(until)
    }

    /// - Returns: true if the deadline is overdue with respect to the passed in `now` time instant
    internal func isOverdue() -> Bool {
        self.isBefore(.now)
    }

    internal func isBefore(_ until: ContinuousClock.Instant) -> Bool {
        self < until
    }

}
