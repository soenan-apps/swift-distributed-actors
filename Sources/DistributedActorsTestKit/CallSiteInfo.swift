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

import Foundation
import XCTest

/// Source location and assertion name used when reporting a failure.
public struct CallSiteInfo {
    /// Source file containing the assertion.
    public let file: StaticString
    /// One-based assertion line.
    public let line: UInt
    /// One-based assertion column.
    public let column: UInt
    /// Assertion function name, including its opening parenthesis.
    public let appliedAssertionName: String

    internal init(
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        function: String = #function
    ) {
        self.file = file
        self.line = line
        self.column = column
        guard let openingParenthesis = function.firstIndex(of: "(") else {
            preconditionFailure("Assertion function names must contain an opening parenthesis")
        }
        self.appliedAssertionName = String(function[function.startIndex...openingParenthesis])
    }

    /// Prepares a detailed error, specialized for two values being equal
    ///
    /// - Warning: Performs file IO in order to read source location line where failure happened
    internal func notEqualError<Got, Expected>(
        got value: Got,
        expected: Expected,
        failTest: Bool = true
    ) -> CallSiteError {
        let padding: String = String(repeating: " ", count: "[error]".count)
        return self.error(
            """
            [\(value)]
            does not equal expected:
            \(padding)[\(expected)]\n
            """,
            failTest: failTest
        )
    }

    /// - Warning: Performs file IO in order to read source location line where failure happened
    internal func equalError<Got, Expected>(
        got value: Got,
        unexpectedEqual: Expected,
        failTest: Bool = true
    ) -> CallSiteError {
        self.error("[\(value)] does equal: [\(unexpectedEqual)]\n", failTest: failTest)
    }

    /// Returns an Error that should be thrown by the called.
    /// Includes the message and source location so the failed assertion can be located.
    public func error(_ message: String, failTest: Bool = true) -> CallSiteError {
        if failTest, !ActorTestKit.isInRepeatableContext() {
            XCTFail(message, file: self.file, line: self.line)
        }

        return CallSiteError(callSite: self, explained: message)
    }

    /// Prepares a detailed error, specialized for a prefix mismatch of a string
    ///
    /// - Warning: Performs file IO in order to read source location line where failure happened
    internal func notMatchingPrefixError(
        got value: any StringProtocol,
        expected: any StringProtocol,
        failTest: Bool = true
    ) -> CallSiteError {
        let padding: String = String(repeating: " ", count: "[error]".count)
        return self.error(
            """
            [\(value)]
            does start with expected prefix:
            \(padding)[\(expected)]\n
            """,
            failTest: failTest
        )
    }
}
