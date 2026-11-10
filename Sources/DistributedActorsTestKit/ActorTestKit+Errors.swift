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

import DistributedActorsConcurrencyHelpers
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

extension ActorTestKit {
    /// Returns an error that can be used when conditions in tests are not met. This is especially useful in
    /// calls to `testKit.eventually`, where a condition is checked multiple times, until it is successful
    /// or times out.
    ///
    /// Examples:
    ///
    ///     testKit.eventually(within: .seconds(3)) {
    ///         guard ... else { throw testKit.error("failed to extract expected information") }
    ///     }
    public func error(
        _ message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Error {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let fullMessage: String = message ?? "<no message>"
        return callSite.error(fullMessage, failTest: false)
    }

    /// Returns a failure with additional callsite information and fails the test.
    ///
    /// Examples:
    ///
    ///     guard ... else { throw testKit.fail("failed to extract expected information") }
    public func fail(
        _ message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Error {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let fullMessage: String = message ?? "<no message>"
        return callSite.error(fullMessage, failTest: true)
    }
}
