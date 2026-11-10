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

/// Failures raised when an expected throw does not match the observed result.
public enum ShouldMatcherError: Error {
    /// The tested block returned instead of throwing.
    case expectedErrorToBeThrown
    /// The tested block threw unexpectedly.
    case unexpectedErrorWasThrown
}

/// Asserts that the block throws the expected error type.
public func shouldThrow<E: Error, T>(
    expected: E.Type,
    file: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column,
    _ block: () throws -> T
) throws {
    let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
    let thrownError: Error = try shouldThrow(file: file, line: line, column: column, block)
    guard thrownError is E else {
        let error: CallSiteError = callSiteInfo.error("Expected block to throw [\(expected)], but threw: "
            + "[\(thrownError)]")
        XCTFail("\(error)", file: callSiteInfo.file, line: callSiteInfo.line)
        throw error
    }
}

/// If this function throws, the wrapped block did NOT throw.
@discardableResult
public func shouldThrow<T>(
    file: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column,
    _ block: () throws -> T
) throws -> Error {
    let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
    let result: T
    do {
        result = try block()
    } catch {
        return error
    }
    let error: CallSiteError = callSiteInfo.error("Expected block to throw, but returned: [\(result)]")
    XCTFail("\(error)", file: callSiteInfo.file, line: callSiteInfo.line)
    throw error
}

/// If this function throws, the wrapped block did NOT throw.
@discardableResult
public func shouldThrow<T>(
    file: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column,
    _ block: () async throws -> T
) async throws -> Error {
    let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
    let result: T
    do {
        result = try await block()
    } catch {
        return error
    }
    let error: CallSiteError = callSiteInfo.error("Expected block to throw, but returned: [\(result)]")
    XCTFail("\(error)", file: callSiteInfo.file, line: callSiteInfo.line)
    throw error
}

/// Reports an unexpected thrown error with the original assertion location.
public func shouldNotThrow<T>(
    file: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column,
    _ block: () async throws -> T
) async throws -> T {
    let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
    do {
        return try await block()
    } catch {
        XCTFail("\(error)", file: callSiteInfo.file, line: callSiteInfo.line)
        throw callSiteInfo.error("Should not have thrown, but did:\n" + "\(error)")
    }
}

/// Reports unexpected thrown errors with the original assertion location.
public func shouldNotThrow<T>(
    file: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column,
    _ block: () throws -> T
) throws -> T {
    let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
    do {
        return try block()
    } catch {
        XCTFail("\(error)", file: callSiteInfo.file, line: callSiteInfo.line)
        throw callSiteInfo.error("Should not have thrown, but did:\n" + "\(error)")
    }
}

/// Creates a failure for an unexpected execution path.
public func shouldNotHappen(
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) -> Error {
    let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
    return callSiteInfo.error("Should not happen: \(message)")
}
