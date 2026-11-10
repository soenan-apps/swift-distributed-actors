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

import NIO

// Modified by Soenan for musl platform support.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: utilities to convert between Duration and C timespec

private let kNanosecondsPerSecond: Int = 1_000_000_000

/// C time representation used by duration conversion.
@usableFromInline
internal typealias TimeSpec = timespec

extension TimeSpec {
    @usableFromInline
    internal static func from(duration: Duration) -> timespec {
        let seconds: Int = Int(duration.nanoseconds) / kNanosecondsPerSecond
        let nanos: Int = Int(duration.nanoseconds) % kNanosecondsPerSecond
        var time: timespec = timespec()
        time.tv_sec = seconds
        time.tv_nsec = nanos
        return time
    }

    @usableFromInline
    internal static func + (lhs: timespec, rhs: timespec) -> timespec {
        let totalNanos: Int64 = lhs.toNanos() + rhs.toNanos()
        var result: timespec = timespec()
        result.tv_sec = Int(totalNanos / Int64(kNanosecondsPerSecond))
        result.tv_nsec = Int(totalNanos % Int64(kNanosecondsPerSecond))
        return result
    }

    @usableFromInline
    internal func toNanos() -> Int64 {
        Int64(self.tv_nsec) + (Int64(self.tv_sec) * Int64(kNanosecondsPerSecond))
    }
}
