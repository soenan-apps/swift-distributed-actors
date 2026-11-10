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

import CDistributedActorsMailbox  // for backtrace
import DistributedActorsConcurrencyHelpers
import Foundation

// Modified by Soenan for explicit pthread imports on musl.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// swiftlint:disable unavailable_function
/// Terminates with a diagnostic including the expected result type and caller location.
/// Used where runtime contracts deliberately cannot produce a value.
public func undefined<T>(
    hint: String = "",
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
) -> T {
    let message: String = hint.isEmpty ? "" : ": \(hint)"
    fatalError("undefined \(function) -> \(T.self)\(message)", file: file, line: line)
}
// swiftlint:enable unavailable_function

/// Terminates with a diagnostic identifying the caller and optional hint.
public func undefined(
    hint: String = "",
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line
) -> Never {
    let message: String = hint.isEmpty ? "" : ": \(hint)"
    fatalError("undefined \(function) -> Never \(message)", file: file, line: line)
}

// swiftlint:disable unavailable_function
/// Terminates with a backtrace and the supplied diagnostic at the caller location.
@usableFromInline
internal func fatalErrorBacktrace<T>(_ hint: String, file: StaticString = #file, line: UInt = #line) -> T {
    sact_dump_backtrace()
    fatalError(hint, file: file, line: line)
}
// swiftlint:enable unavailable_function

/// Asserts a condition, dumping a backtrace before a failed assertion.
internal func assertBacktrace(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = String(),
    file: StaticString = #file,
    line: UInt = #line
) {
    assert(
        condition(),
        { () in
            sact_dump_backtrace()
            return message()
        }(),
        file: file,
        line: line
    )
}

private func createTimeFormatter() -> DateFormatter {
    let formatter: DateFormatter = DateFormatter()
    formatter.dateFormat = "H:m:ss.SSSS"
    formatter.locale = Locale(identifier: "en_US")
    formatter.calendar = Calendar(identifier: .gregorian)
    return formatter
}

/// Short for "pretty print", useful for debug tracing
internal func pprint(_ message: String, function: String = #function, file: String = #fileID, line: UInt = #line) {
    print(
        """
        [pprint]\
        [\(createTimeFormatter().string(from: Date()))] \
        [\(file):\(line)] \
        (\(function)) \
        \(message)
        """
    )
}

/// Prints a timestamped diagnostic at the caller location.
internal func pprint(_ message: String, metadata: [String: Any], file: String = #fileID, line: UInt = #line) {
    print(
        """
        [pprint]\
        [\(createTimeFormatter().string(from: Date()))] \
        [\(file):\(line)]\
        {\(metadata.map { "\($0):\($1)" }.joined(separator: ";"))}
        [\(currentPThreadThreadID())]: \
        \(message)
        """
    )
}

/// Prints a timestamped diagnostic at the caller location.
internal func pprint(_ message: StaticString, file: String = #fileID, line: UInt = #line) {
    print(
        """
        [pprint]\
        [\(createTimeFormatter().string(from: Date()))] \
        [\(file):\(line)]\
        [\(currentPThreadThreadID())]: \
        \(message)
        """
    )
}

/// Prints a timestamped diagnostic at the caller location.
internal func pprint(_ message: StaticString, metadata: [String: Any], file: String = #fileID, line: UInt = #line) {
    print(
        """
        [pprint]\
        [\(createTimeFormatter().string(from: Date()))] \
        [\(file):\(line)]\
        {\(metadata.map { "\($0):\($1)" }.joined(separator: ";"))}
        [\(currentPThreadThreadID())]: \
        \(message)
        """
    )
}

internal let kConsoleReset: String = "\u{001B}[0;0m"
internal let kConsoleBold: String = "\u{001B}[1m"
internal let kConsoleYellow: String = "\u{001B}[0;33m"
internal let kConsoleGreen: String = "\u{001B}[0;32m"

/// Like [pprint] but yellow, use for things that are better not to miss.
internal func pnote(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
    print(
        """
        \(kConsoleYellow)\
        [\(createTimeFormatter().string(from: Date()))] \
        \(file):\(line) : \(message)\
        \(kConsoleReset)
        """
    )
}

/// Like [pprint] but green, use for notable "good" output.
internal func pinfo(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
    print(
        """
        \(kConsoleGreen)\
        [\(createTimeFormatter().string(from: Date()))] \
        \(file):\(line) : \(message)\
        \(kConsoleReset)
        """
    )
}

internal func currentPThreadThreadID() -> String {
    #if os(macOS)
    var threadId: UInt64 = 0
    _ = pthread_threadid_np(nil, &threadId)
    #else
    let threadId: pthread_t = pthread_self()
    #endif

    return "thread:\(threadId)"
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Functions used for debug tracing, eventually likely to be removed

/// INTERNAL API: Used for easier debugging; most of those messages are meant to be eventually removed
internal func traceLog_DeathWatch(_ message: @autoclosure () -> String, file: String = #fileID, line: UInt = #line) {
    #if SACT_TRACE_DEATHWATCH
    pprint("SACT_TRACE_DEATHWATCH: \(message())", file: file, line: line)
    #endif
}

/// INTERNAL API: Used for easier debugging; most of those messages are meant to be eventually removed
internal func traceLog_Mailbox(
    _ path: ActorPath?,
    _ message: @autoclosure () -> String,
    file: String = #fileID,
    line: UInt = #line
) {
    #if SACT_TRACE_MAILBOX
    pprint(
        "SACT_TRACE_MAILBOX(\(path.map { "\($0)" } ?? "<unknown>")): \(message())",
        file: file,
        line: line
    )
    #endif
}

/// INTERNAL API: Used for easier debugging; most of those messages are meant to be eventually removed
internal func traceLog_Cell(_ message: @autoclosure () -> String, file: String = #fileID, line: UInt = #line) {
    #if SACT_TRACE_ACTOR_CELL
    pprint("SACT_TRACE_ACTOR_CELL: \(message())", file: file, line: line)
    #endif
}

/// INTERNAL API: Used for easier debugging; most of those messages are meant to be eventually removed
internal func traceLog_Probe(_ message: @autoclosure () -> String, file: String = #fileID, line: UInt = #line) {
    #if SACT_TRACE_PROBE
    pprint("SACT_TRACE_PROBE: \(message())", file: file, line: line)
    #endif
}

/// INTERNAL API: Used for easier debugging; most of those messages are meant to be eventually removed
internal func traceLog_Supervision(_ message: @autoclosure () -> String, file: String = #fileID, line: UInt = #line) {
    #if SACT_TRACE_SUPERVISION
    pprint("SACT_TRACE_SUPERVISION: \(message())", file: file, line: line)
    #endif
}

/// INTERNAL API: Used for easier debugging; most of those messages are meant to be eventually removed
internal func traceLog_Serialization(_ message: @autoclosure () -> String, file: String = #fileID, line: UInt = #line) {
    #if SACT_TRACE_SERIALIZATION
    pprint("SACT_TRACE_SERIALIZATION: \(message())", file: file, line: line)
    #endif
}

/// INTERNAL API: Used for easier debugging; most of those messages are meant to be eventually removed
internal func traceLog_Remote(
    _ node: Cluster.Node,
    _ message: @autoclosure () -> String,
    file: String = #fileID,
    line: UInt = #line
) {
    #if SACT_TRACE_REMOTE
    pprint("SACT_TRACE_REMOTE [\(node)]: \(message())", file: file, line: line)
    #endif
}

// MARK: reusable "take(right)" etc. functions

@inlinable
internal func identity<T>(_ param: T) -> T {
    param
}

@inlinable
internal func right<L, R>(left _: L, right: R) -> R {
    right
}

@inlinable
internal func left<L, R>(left: L, right _: R) -> L {
    left
}

// MARK: Minor printing/formatting helpers
