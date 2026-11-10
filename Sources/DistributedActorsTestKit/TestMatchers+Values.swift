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

extension TestMatchers where T: Equatable {
    /// Asserts equality with the expected value.
    public func toEqual(_ expected: T) {
        if self.value != expected {
            let error: CallSiteError = self.callSite.notEqualError(got: self.value, expected: expected)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts inequality with the unexpected value.
    public func toNotEqual(_ unexpectedEqual: T) {
        if self.value == unexpectedEqual {
            let error: CallSiteError = self.callSite.equalError(got: self.value, unexpectedEqual: unexpectedEqual)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts that the value has the expected runtime type.
    public func toBe<Other>(_ expected: Other.Type) {
        if !(self.value is Other) {
            let error: CallSiteError = self.callSite.notEqualError(got: self.value, expected: expected)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }
}

extension TestMatchers where T == String {
    /// Asserts that `value` contains the `subString`.
    public func toContain(_ subString: String, negate: Bool = false) {
        let contains: Bool = self.value.contains(subString)
        if (negate && contains) || (!negate && !contains) {
            // fancy printout:
            let negateString: String = negate ? "NOT " : ""
            var message: String = "Expected String [\(value)] to \(negateString)contain: ["
            if kIsTty {
                message += "\(ANSIColors.bold.rawValue)"
            }
            message += "\(subString)"
            if kIsTty {
                message += "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue)"
            }
            message += "]"
            let error: CallSiteError = self.callSite.error(message)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts that `value` does NOT contain the `subString`.
    public func toNotContain(_ subString: String) {
        self.toContain(subString, negate: true)
    }
}

extension TestMatchers where T: Comparable {
    /// Asserts strict ordering below the expected value.
    public func toBeLessThan(_ expected: T) {
        if !(self.value < expected) {
            let error: CallSiteError = self.callSite.error("\(self.value) is not less than \(expected)")
            XCTAssertLessThan(self.value, expected, "\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts ordering at or below the expected value.
    public func toBeLessThanOrEqual(_ expected: T) {
        if !(self.value <= expected) {
            let error: CallSiteError = self.callSite.error("\(self.value) is not less than or equal \(expected)")
            XCTAssertLessThanOrEqual(
                self.value, expected, "\(error)", file: self.callSite.file, line: self.callSite.line
            )
        }
    }

    /// Asserts strict ordering above the expected value.
    public func toBeGreaterThan(_ expected: T) {
        if !(self.value > expected) {
            let error: CallSiteError = self.callSite.error("\(self.value) is not greater than \(expected)")
            XCTAssertGreaterThan(self.value, expected, "\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts ordering at or above the expected value.
    public func toBeGreaterThanOrEqual(_ expected: T) {
        if !(self.value >= expected) {
            let error: CallSiteError = self.callSite.error("\(self.value) is not greater than or equal \(expected)")
            XCTAssertGreaterThanOrEqual(
                self.value,
                expected,
                "\(error)",
                file: self.callSite.file,
                line: self.callSite.line
            )
        }
    }
}

extension TestMatchers where T: Collection {
    /// Asserts that `value` is empty
    public func toBeEmpty() {
        if !self.value.isEmpty {
            let message: String = "Expected [\(value)] to be empty"
            let error: CallSiteError = self.callSite.error(message)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts that `value` is not empty
    public func toBeNotEmpty() {
        if self.value.isEmpty {
            let message: String = "Expected [\(value)] to to be non-empty"
            let error: CallSiteError = self.callSite.error(message)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }
}
