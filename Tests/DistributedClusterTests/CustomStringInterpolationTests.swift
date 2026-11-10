// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
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

internal final class CustomStringInterpolationTests: XCTestCase {
    internal func test_leftPadTo_whenValueShorterThanPadTo() {
        let padded: String = "\("hello world", leftPadTo: 16)"
        padded.count.shouldEqual(16)
        padded.shouldEqual("     hello world")
    }

    internal func test_leftPadTo_whenValueLongerThanPadTo() {
        let phrase: String = "hello world"
        let padded: String = "\(phrase, leftPadTo: 4)"
        padded.count.shouldEqual(phrase.count)
        padded.shouldEqual(phrase)
    }

    internal func test_leftPadTo_whenValueEqualThanPadTo() {
        let phrase: String = "hello world"
        let padded: String = "\(phrase, leftPadTo: phrase.count)"
        padded.count.shouldEqual(phrase.count)
        padded.shouldEqual(phrase)
    }
}
