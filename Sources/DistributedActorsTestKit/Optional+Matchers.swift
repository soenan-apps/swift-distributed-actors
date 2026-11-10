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

extension Optional {
    /// Asserts that this optional contains no value.
    public func shouldBeNil(file: StaticString = #filePath, line: UInt = #line, column: UInt = #column) {
        if self != nil {
            let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
            let error: CallSiteError = callSite.error("Expected nil, got [\(String(describing: self))]")
            XCTAssertNil(self, "\(error)", file: callSite.file, line: callSite.line)
        }
    }

    /// Asserts that this optional contains a value.
    public func shouldNotBeNil(file: StaticString = #filePath, line: UInt = #line, column: UInt = #column) {
        if self == nil {
            let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
            let error: CallSiteError = callSite.error("Expected not nil, got [\(String(describing: self))]")
            XCTAssertNotNil(self, "\(error)", file: callSite.file, line: callSite.line)
        }
    }
}

extension Set {
    /// Asserts set equality and describes missing and unexpected elements.
    public func shouldEqual(
        _ other: Self,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let rhs: Self = other
        if self == rhs {
            ()
        } else {
            var message: String = "Set \(rhs) did not equal \(self)."
            let rhsMinusSelf: Self = rhs.subtracting(self)
            if !rhsMinusSelf.isEmpty {
                message += "\nElements present in `other` but not `self`:"
                message += "\n    \(rhsMinusSelf)"
            }
            let selfMinusRhs: Self = self.subtracting(rhs)
            if !selfMinusRhs.isEmpty {
                message += "\nElements present in `self` but not `other`:"
                message += "\n    \(selfMinusRhs)"
            }
            XCTAssertEqual(
                self,
                rhs,
                "\(callSiteInfo.error(message))",
                file: callSiteInfo.file,
                line: callSiteInfo.line
            )
        }
    }
}

extension Equatable {
    /// Asserts that the value is equal to the `other` value
    public func shouldEqual(
        _ other: Self,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: callSiteInfo).toEqual(other)
    }

    /// Asserts that the value is of the expected Type `T`
    public func shouldBe<T>(
        _ expectedType: T.Type,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: callSiteInfo).toBe(expectedType)
    }

    /// Asserts inequality with the supplied value.
    public func shouldNotEqual(
        _ other: Self,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: callSiteInfo).toNotEqual(other)
    }
}

extension Hashable {
    /// Asserts that the value is an element in the given set
    public func shouldBeIn(
        _ set: Set<Self>,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        if set.contains(self) {
            ()
        } else {
            let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
            let error: CallSiteError = callSite.error("Expected \(self) to be an item in \(set)")
            XCTFail("\(error)", file: callSite.file, line: callSite.line)
        }
    }
}

extension Bool {
    /// Asserts the expected Boolean value.
    public func shouldBe(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line, column: UInt = #column) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toEqual(expected)
    }

    /// Asserts that the value is false.
    public func shouldBeFalse(file: StaticString = #filePath, line: UInt = #line, column: UInt = #column) {
        self.shouldBe(false, file: file, line: line, column: column)
    }

    /// Asserts that the value is true.
    public func shouldBeTrue(file: StaticString = #filePath, line: UInt = #line, column: UInt = #column) {
        self.shouldBe(true, file: file, line: line, column: column)
    }
}

extension Comparable {
    /// Asserts strict ordering below the supplied value.
    public func shouldBeLessThan(
        _ expected: Self,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toBeLessThan(expected)
    }

    /// Asserts ordering at or below the supplied value.
    public func shouldBeLessThanOrEqual(
        _ expected: Self,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toBeLessThanOrEqual(expected)
    }

    /// Asserts strict ordering above the supplied value.
    public func shouldBeGreaterThan(
        _ expected: Self,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toBeGreaterThan(expected)
    }

    /// Asserts ordering at or above the supplied value.
    public func shouldBeGreaterThanOrEqual(
        _ expected: Self,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toBeGreaterThanOrEqual(expected)
    }
}
// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Collection `should*` matchers
extension Collection {
    /// Asserts that the collection contains no elements.
    public func shouldBeEmpty(file: StaticString = #filePath, line: UInt = #line, column: UInt = #column) {
        let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: callSiteInfo).toBeEmpty()
    }

    /// Asserts that the collection contains elements.
    public func shouldBeNotEmpty(file: StaticString = #filePath, line: UInt = #line, column: UInt = #column) {
        let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: callSiteInfo).toBeNotEmpty()
    }
}

extension Collection where Element: Equatable {
    /// Asserts that the collection begins with the supplied prefix.
    public func shouldStartWith<PossiblePrefix>(
        prefix: PossiblePrefix,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    )
    where PossiblePrefix: Collection, Element == PossiblePrefix.Element {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toStartWith(prefix: prefix)
    }

    /// Asserts that the collection ends with the supplied suffix.
    public func shouldEndWith<PossibleSuffix>(
        suffix: PossibleSuffix,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    )
    where PossibleSuffix: Collection, Element == PossibleSuffix.Element {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toEndWith(suffix: suffix)
    }

    /// Asserts that the collection or string contains the supplied element.
    public func shouldContain(
        _ element: Element,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toContain(element)
    }

    /// Asserts that the collection or string excludes the supplied element.
    public func shouldNotContain(
        _ element: Element,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toNotContain(element)
    }

    /// Applies the `where` predicate while trying to locate at least one element in the collection.
    /// Asserts that the collection or string contains the supplied element.
    public func shouldContain(
        where predicate: (Element) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toContain { predicate($0) }
    }
}

extension String {
    /// Asserts that the collection or string contains the supplied element.
    public func shouldContain(
        _ element: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toContain(element)
    }

    /// Asserts that the collection or string excludes the supplied element.
    public func shouldNotContain(
        _ element: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let csInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        return TestMatchers(value: self, callSite: csInfo).toNotContain(element)
    }
}
