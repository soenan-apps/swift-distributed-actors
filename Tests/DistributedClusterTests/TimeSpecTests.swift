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

import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

private let kNanosecondsPerSecond: Int = 1_000_000_000

internal final class TimeSpecTests: XCTestCase {
    private let nanosDuration: Duration = .nanoseconds(100)
    private let secondsDuration: Duration = .seconds(2)
    private var totalDuration: Duration {
        self.secondsDuration + self.nanosDuration
    }

    private var nanos: TimeSpec {
        .from(duration: self.nanosDuration)
    }

    private var seconds: TimeSpec {
        .from(duration: self.secondsDuration)
    }

    private var total: TimeSpec {
        .from(duration: self.totalDuration)
    }

    internal func test_timeSpecShouldBeCreatedProperlyFromDuration() {
        self.total.toNanos().shouldEqual(Int64(self.totalDuration.nanoseconds))
        self.total.tv_sec.shouldEqual(Int(self.totalDuration.nanoseconds) / kNanosecondsPerSecond)
        self.total.tv_nsec.shouldEqual(Int(self.totalDuration.nanoseconds) % kNanosecondsPerSecond)
    }

    internal func test_timeSpecAdd() {
        let sum: TimeSpec = self.nanos + self.seconds

        sum.shouldEqual(self.total)
    }

    internal func test_lessThan() {
        XCTAssertTrue(self.nanos < self.seconds)
        XCTAssertFalse(self.seconds < self.nanos)
        XCTAssertFalse(self.total < .from(duration: self.totalDuration))
    }

    internal func test_greaterThan() {
        XCTAssertFalse(self.nanos > self.seconds)
        XCTAssertTrue(self.seconds > self.nanos)
    }

    internal func test_equals() {
        XCTAssertNotEqual(self.nanos, self.seconds)
        XCTAssertNotEqual(self.seconds, self.nanos)

        XCTAssertEqual(self.nanos, .from(duration: self.nanosDuration))
        XCTAssertEqual(self.seconds, .from(duration: self.secondsDuration))
        XCTAssertEqual(self.total, .from(duration: self.totalDuration))
    }
}

extension TimeSpec: @retroactive Comparable {
    public static func < (lhs: TimeSpec, rhs: TimeSpec) -> Bool {
        lhs.tv_sec < rhs.tv_sec || (lhs.tv_sec == rhs.tv_sec && lhs.tv_nsec < rhs.tv_nsec)
    }

    public static func == (lhs: TimeSpec, rhs: TimeSpec) -> Bool {
        lhs.tv_sec == rhs.tv_sec
    }
}
