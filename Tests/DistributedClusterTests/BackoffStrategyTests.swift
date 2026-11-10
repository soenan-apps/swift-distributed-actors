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

internal final class BackoffStrategyTests: XCTestCase {
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Constant backoff

    internal func test_constantBackoff_shouldAlwaysYieldSameDuration() {
        let backoff: ConstantBackoffStrategy = Backoff.constant(.milliseconds(100))
        backoff.next()?.shouldEqual(.milliseconds(100))
        backoff.next()?.shouldEqual(.milliseconds(100))
        backoff.next()?.shouldEqual(.milliseconds(100))
    }

    internal func test_constantBackoff_reset_shouldDoNothing() {
        let backoff: ConstantBackoffStrategy = Backoff.constant(.milliseconds(100))
        backoff.next()?.shouldEqual(.milliseconds(100))
        backoff.reset()
        backoff.next()?.shouldEqual(.milliseconds(100))
        backoff.reset()
        backoff.next()?.shouldEqual(.milliseconds(100))
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Exponential backoff

    internal func test_exponentialBackoff_shouldIncreaseBackoffEachTime() throws {
        var backoff: ExponentialBackoffStrategy = Backoff.exponential(initialInterval: .milliseconds(100))
        let firstBehavior: Duration = try XCTUnwrap(backoff.next())
        firstBehavior.shouldBeGreaterThanOrEqual(Duration.milliseconds(75))
        firstBehavior.shouldBeLessThanOrEqual(Duration.milliseconds(130))

        let secondBehavior: Duration = try XCTUnwrap(backoff.next())
        secondBehavior.shouldBeGreaterThanOrEqual(Duration.milliseconds(100))
        secondBehavior.shouldBeLessThanOrEqual(Duration.milliseconds(260))
    }

    internal func test_exponentialBackoff_shouldAllowDisablingRandomFactor() {
        var backoff: ExponentialBackoffStrategy = Backoff.exponential(
            initialInterval: .milliseconds(100),
            randomFactor: 0
        )
        backoff.next()?.shouldEqual(.milliseconds(100))
        backoff.next()?.shouldEqual(.milliseconds(150))

        backoff.next()?.shouldEqual(.nanoseconds(225_000_000))

        backoff.next()?.shouldEqual(.nanoseconds(337_500_000))
    }

    internal func test_exponentialBackoff_reset_shouldResetBackoffIntervals() {
        var backoff: ExponentialBackoffStrategy = Backoff.exponential(
            initialInterval: .milliseconds(100),
            randomFactor: 0
        )
        backoff.next()?.shouldEqual(.milliseconds(100))
        backoff.next()?.shouldEqual(.milliseconds(150))
        backoff.reset()
        backoff.next()?.shouldEqual(.milliseconds(100))
        backoff.next()?.shouldEqual(.milliseconds(150))
    }

    internal func test_exponentialBackoff_shouldNotExceedMaximumBackoff() {
        let max: Duration = Duration.seconds(1)
        let maxRandomNoise: Duration = max * 1.25
        var backoff: ExponentialBackoffStrategy = Backoff.exponential(
            initialInterval: .milliseconds(500),
            capInterval: max
        )
        backoff.next()?.shouldBeLessThanOrEqual(max + maxRandomNoise)
        backoff.next()?.shouldBeLessThanOrEqual(max + maxRandomNoise)
        backoff.next()?.shouldBeLessThanOrEqual(max + maxRandomNoise)
        backoff.next()?.shouldBeLessThanOrEqual(max + maxRandomNoise)
    }

    internal func test_exponentialBackoff_shouldStopAfterMaxAttempts() throws {
        let maxAttempts: Int = 3
        var backoff: ExponentialBackoffStrategy = Backoff.exponential(
            initialInterval: .milliseconds(500),
            randomFactor: 0,
            maxAttempts: maxAttempts
        )
        try XCTUnwrap(backoff.next()).shouldEqual(.milliseconds(500))
        try XCTUnwrap(backoff.next()).shouldEqual(.milliseconds(750))
        try XCTUnwrap(backoff.next()).shouldEqual(.milliseconds(1_125))
        backoff.next().shouldBeNil()
        backoff.next().shouldBeNil()
        backoff.next().shouldBeNil()
    }

    internal func test_exponentialBackoff_withLargeInitial_shouldAdjustCap() {
        _ = Backoff.exponential(
            initialInterval: .seconds(
                60
            )
        )  // cap used to be hardcoded which would cause this to precondition crash
    }
}
