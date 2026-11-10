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
import XCTest

import struct Foundation.Date

@testable import DistributedCluster
@testable import Logging

/// Testing only utility: Captures all log statements for later inspection.
///
/// ### Warning
/// This handler uses locks for each and every operation.
public final class LogCapture {
    /// Selects the log levels, actor paths, text, and metadata captured by a test.
    public struct Settings {
        /// Lowest captured severity.
        public var minimumLogLevel: Logger.Level

        /// Filter and capture logs only from actors with the following path prefix
        public var filterActorPaths: Set<String> = [""]
        /// Do not capture log messages which include the following strings.
        public var excludeActorPaths: Set<String> = []

        /// Do not capture log messages which include the following strings.
        public var excludeGrep: Set<String> = []
        /// Capture only messages containing one of these strings when nonempty.
        public var grep: Set<String> = []

        /// Metadata keys omitted when printing captured logs.
        public var ignoredMetadata: Set<String> = [
            "cluster/node"
        ]

        /// Creates settings that capture every log message.
        public init() {
            self.minimumLogLevel = .trace
        }
    }

    private var _logs: [CapturedLogMessage] = []
    private let lock: DistributedActorsConcurrencyHelpers.Lock = DistributedActorsConcurrencyHelpers.Lock()

    internal let settings: Settings
    private var captureLabel: String = ""

    /// Snapshot of all captured messages.
    public var logs: [CapturedLogMessage] {
        self.lock.withLock {
            self._logs
        }
    }

    /// Snapshot of captured messages marked as dead letters.
    public var deadLetterLogs: [CapturedLogMessage] {
        self.lock.withLock {
            self._logs.filter { message in
                message.metadata?.keys.contains("deadLetter") ?? false
            }
        }
    }

    /// Creates a capture with the supplied filters.
    public init(settings: Settings = .init()) {
        self.settings = settings
    }

    /// Returns a logger that appends to this capture.
    public func logger(label: String) -> Logger {
        self.captureLabel = label
        return Logger(label: "LogCapture(\(label))", LogCaptureLogHandler(label: label, self))
    }

    internal func append(_ log: CapturedLogMessage) {
        self.lock.withLockVoid {
            self._logs.append(log)
        }
    }

    /// Blocks while calling thread while waiting for log message to appear from monitored actor system.
    ///
    /// Returns: first log message that matches text predicate (with naive "contains" check).
    /// Throws: an ``EventuallyError`` when the deadline is exceeded without matching a log message.
    @discardableResult
    public func awaitLogContaining(
        _ testKit: ActorTestKit,
        text: String,
        within: Duration = .seconds(3),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CapturedLogMessage {
        try testKit.eventually(within: within, file: file, line: line) {
            let capturedLogs: [CapturedLogMessage] = self.logs
            guard let found = capturedLogs.first(where: { log in "\(log)".contains(text) }) else {
                throw TestError("Logs did not contain [\(text)].")
            }

            return found
        }
    }

    /// Prints captured logs if the supplied test run failed.
    public func printIfFailed(_ testRun: XCTestRun?) {
        if let failureCount = testRun?.failureCount, failureCount > 0 {
            print(String(repeating: "-", count: 120))
            self.printLogs()
            print(String(repeating: "=", count: 120))
        }
    }

    /// Prints captured logs and filtered metadata for failure diagnostics.
    public func printLogs() {
        for log in self.logs {
            var metadataString: String = ""
            var actorIdentifier: String = ""
            if var metadata = log.metadata {
                if let id = metadata.removeValue(forKey: "actor/id") {
                    actorIdentifier = "[\(id)]"
                    _ = metadata.removeValue(forKey: "actor/path")  // discard it
                } else if let path = metadata.removeValue(forKey: "actor/path") {
                    actorIdentifier = "[\(path)]"
                }

                metadata.removeValue(forKey: "label")
                for ignoreKey in self.settings.ignoredMetadata {
                    metadata.removeValue(forKey: ignoreKey)
                }
                if !metadata.isEmpty {
                    metadataString = "\n"
                    for key in metadata.keys.sorted() {
                        guard let value = metadata[key] else {
                            preconditionFailure("Sorted metadata key must be present")
                        }
                        let valueDescription: String = self.prettyPrint(metadata: value)

                        var allString: String = "\n\"\(key)\": \(valueDescription)"
                        if allString.contains("\n") {
                            allString = String(
                                allString.split(separator: "\n").map { valueLine in
                                    if valueLine.starts(with: "// ") {
                                        return "[captured] [\(self.captureLabel)] \(valueLine)\n"
                                    }
                                    return "[captured] [\(self.captureLabel)] // \(valueLine)\n"
                                }.joined()
                            )
                        }
                        metadataString.append(allString)
                    }
                    metadataString = String(metadataString.dropLast(1))
                }
            }
            let date: String = ActorOriginLogHandler.createSimpleFormatter().string(from: log.date)
            let file: Substring = log.file.split(separator: "/").last ?? ""
            let line: UInt = log.line
            print(
                "[captured] [\(self.captureLabel)] \(date) \(log.level) \(actorIdentifier) "
                    + "[\(file):\(line)] \(log.message)\(metadataString)"
            )
        }
    }

    internal func prettyPrint(metadata: Logger.MetadataValue) -> String {
        let consoleReset: String = "\u{001B}[0;0m"
        let consoleBold: String = "\u{001B}[1m"

        var valueDescription: String = ""
        switch metadata {
        case .string(let string):
            valueDescription = string

        case .stringConvertible(let convertible as CustomPrettyStringConvertible):
            valueDescription = convertible.prettyDescription

        case .stringConvertible(let convertible):
            valueDescription = convertible.description

        case .array(let array):
            valueDescription = "\n  \(array.map { "\($0)" }.joined(separator: "\n  "))"

        case .dictionary(let dictionary):
            for key in dictionary.keys {
                guard let value = dictionary[key] else {
                    preconditionFailure("Dictionary key must be present")
                }
                valueDescription += "\(consoleBold)\(key)\(consoleReset): \(self.prettyPrint(metadata: value))"
            }
        }

        return valueDescription
    }

    /// Asserts that a message matching the query requirements was captured *already* (without waiting for it to appear)
    ///
    /// - Parameter message: Surround with `*what*` to search by containment instead of equality.
    @discardableResult
    public func shouldContain(
        prefix: String? = nil,
        message: String? = nil,
        grep: String? = nil,
        at level: Logger.Level? = nil,
        expectedFile: String? = nil,
        expectedLine: Int = -1,
        failTest: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws -> CapturedLogMessage {
        precondition(
            prefix != nil || message != nil || grep != nil || level != nil || expectedFile != nil,
            "At least one query parameter must be not `nil`!"
        )
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)

        let found: CapturedLogMessage? = self.findLog(
            prefix: prefix,
            message: message,
            grep: grep,
            level: level,
            expectedFile: expectedFile,
            expectedLine: expectedLine
        )

        if let found = found {
            return found
        }
        let query: String = [
            prefix.map { "prefix: \"\($0)\"" },
            message.map { "message: \"\($0)\"" },
            grep.map { "grep: \"\($0)\"" },
            level.map { "level: \($0)" } ?? "",
            expectedFile.map { "expectedFile: \"\($0)\"" },
            (expectedLine > -1 ? Optional(expectedLine) : nil).map { "expectedLine: \($0)" },
        ].compactMap { $0 }
            .joined(separator: ", ")

        let failureMessage: String = """
            Did not find expected log, matching query:
                [\(query)]
            in captured logs at \(file):\(line)
            """
        let callSiteError: Error = callSite.error(failureMessage)
        if failTest {
            XCTFail(failureMessage, file: callSite.file, line: callSite.line)
        }
        throw callSiteError
    }

    private func findLog(
        prefix: String?,
        message: String?,
        grep: String?,
        level: Logger.Level?,
        expectedFile: String?,
        expectedLine: Int = -1
    ) -> CapturedLogMessage? {
        self.logs.first { log in
            if let expected = message {
                if expected.first == "*", expected.last == "*" {
                    guard "\(log.message)".contains(expected.dropFirst().dropLast()) else {
                        return false
                    }
                } else if expected != "\(log.message)" {
                    return false
                }
            }
            if let prefix, !"\(log.message)".starts(with: prefix) {
                return false
            }
            if let grep, !"\(log)".contains(grep) {
                return false
            }
            if let level, log.level != level {
                return false
            }
            if let expectedFile, expectedFile != log.file {
                return false
            }
            return expectedLine <= -1 || log.line == expectedLine
        }
    }

    /// Returns messages matching text and all specified metadata values.
    public func grep(_ string: String, metadata metadataQuery: [String: String] = [:]) -> [CapturedLogMessage] {
        self.logs.filter { log in
            guard "\(log)".contains(string) else {
                // mismatch, exclude it
                return false
            }

            if metadataQuery.isEmpty {
                return true
            }

            let metas: Logger.Metadata = log.metadata ?? [:]
            for (queryKey, queryValue) in metadataQuery {
                if let value = metas[queryKey] {
                    if queryValue != "\(value)" {
                        // mismatch, exclude it
                        return false
                    }  // ok, continue checking other keys
                } else {
                    // key did not exist
                    return false
                }
            }

            return true
        }
    }

}
