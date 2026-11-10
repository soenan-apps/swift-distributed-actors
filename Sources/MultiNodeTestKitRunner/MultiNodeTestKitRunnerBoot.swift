// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//
import ArgumentParser
import DistributedCluster
import MultiNodeTestKit
import NIOCore
import NIOPosix
import OrderedCollections

import struct Foundation.Date
import class Foundation.FileHandle
import struct Foundation.URL

#if canImport(Darwin) || canImport(Glibc)
import class Foundation.Process
#endif
@main
internal struct MultiNodeTestKitRunnerBoot {
    internal struct TestFilter {
        private let matcher: String?

        internal init(parse arguments: ArraySlice<String>) {
            if let filterIdx = arguments.firstIndex(of: "--filter") {
                let filterValueIdx: ArraySlice<String>.Index = arguments.index(after: filterIdx)
                if filterValueIdx >= arguments.endIndex {
                    fatalError("No value for `--filter` given! Arguments: \(arguments)")
                }
                self.matcher = arguments[filterValueIdx]
            } else {
                self.matcher = nil
            }
        }
        internal func matches(suiteName: String, testName: String?) -> Bool {
            guard let matcher = self.matcher else {
                return true  // always match if no matcher
            }
            if suiteName.contains(matcher) {
                return true
            }
            if let testName, testName.contains(matcher) {
                return true
            }
            return false
        }
    }
    internal enum RunResult {
        case exit(Int)
        case signal(Int)
    }
    internal enum InterpretedRunResult {
        case crashedAsExpected
        case crashRegexDidNotMatch(regex: String, output: String)
        case outputError(String)
        case passedAsExpected
        case unexpectedRunResult(RunResult)
        /// Passed test case, for whatever
        internal var passed: Bool {
            switch self {
            case .passedAsExpected, .crashedAsExpected:
                return true

            case .crashRegexDidNotMatch, .unexpectedRunResult, .outputError:
                return false
            }
        }
        /// Failed test case, for whatever reason
        internal var failed: Bool {
            !self.passed
        }
    }
    internal struct MultiNodeTestNotFound: Error {
        internal let suite: String
        internal let test: String
    }
    internal static func main() async throws {
        #if !canImport(Darwin) && !canImport(Glibc)
        print("Platform does not support multi-node tests")
        throw ExitCode.failure
        #else
        await Self().run()
        #endif
    }
    internal func allTestsForSuite(_ testSuite: String) -> [(String, MultiNodeTest)] {
        guard let suiteType = kMultiNodeTestSuites.first(where: { testSuite == "\($0)" }) else {
            return []
        }
        let suiteInstance: any MultiNodeTestSuite = suiteType.init()
        var tests: [(String, MultiNodeTest)] = []
        let multiNodeTestDescriptors: [Mirror.Child] = Mirror(reflecting: suiteInstance)
            .children
            .filter { $0.label?.starts(with: "test") ?? false }
        for multiNodeTestDescriptor in multiNodeTestDescriptors {
            multiNodeTestDescriptor.label.flatMap { label in
                (multiNodeTestDescriptor.value as? MultiNodeTest).map { multiNodeTest in
                    var descriptor: MultiNodeTest = multiNodeTest
                    descriptor.suiteNameStorage = testSuite
                    descriptor.testNameStorage = label
                    tests.append((label, descriptor))
                }
            }
        }
        return tests
    }
    internal func findMultiNodeTest(suite: String, testName: String) -> MultiNodeTest? {
        allTestsForSuite(suite)
            .first { $0.0 == testName }?
            .1
    }
    internal func usage() {
        print("ARGS: \(CommandLine.arguments)")
        print("\(CommandLine.arguments.first ?? "\(Self.self)") COMMAND [OPTIONS]")
        print()
        print("COMMAND is:")
        print("  test                         to run all multi-node tests")
        print("       --filter                to filter which tests should be run; Checks against SUITE and TEST name.")
        print("")
        print("Or an INTERNAL COMMAND:")
        print("For debugging purposes, you can also directly run the test binary directly:")
        print("  \(CommandLine.arguments.first ?? "\(Self.self)") _exec SUITE TEST-NAME NODE-NAME")
    }
    internal func run() async {
        signal(SIGPIPE, SIG_IGN)
        var summary: MultiNodeTestSummary = MultiNodeTestSummary()
        switch CommandLine.arguments.dropFirst().first {
        case .some("test"):
            let filter: TestFilter = TestFilter(parse: CommandLine.arguments.dropFirst())
            defer {
                summary.dump()
            }
            await commandTest(summary: &summary, filter: filter)

        case .some("_exec"):
            if let testSuiteName = CommandLine.arguments.dropFirst(2).first,
                let testName = CommandLine.arguments.dropFirst(3).first,
                let nodeName = CommandLine.arguments.dropFirst(4).first,
                let allNodesString = CommandLine.arguments.dropFirst(5).first,
                let allNodes = Optional(MultiNode.parseAllNodes(allNodesString)),
                let multiNodeTest = findMultiNodeTest(suite: testSuiteName, testName: testName) {
                do {
                    try await executeTest(
                        multiNodeTest: multiNodeTest,
                        nodeName: nodeName,
                        allNodes: allNodes
                    )
                } catch {
                    fatalError(
                        "Test '\(testSuiteName).\(testName)' execution threw error on node "
                            + "[\(nodeName)], error:\(error)".red
                    )
                }
            } else {
                fatalError("can't find/create test for \(Array(CommandLine.arguments.dropFirst(2)))")
            }
            exit(CInt(0))

        default:
            usage()
            exit(EXIT_FAILURE)
        }
        exit(CInt(summary.failedTests == 0 ? EXIT_SUCCESS : EXIT_FAILURE))
    }
    internal func makeAllNodesCommandString(nodeNames: OrderedSet<String>, deployNodes _: [(String, Int)]) -> String {
        var nodePort: Int = 7_301
        return nodeNames.map { nodeName in
            var encodedNode: String = ""
            encodedNode += nodeName
            encodedNode += "@"
            encodedNode += "127.0.0.1"
            encodedNode += ":"
            encodedNode += "\(nodePort)"
            nodePort += 1
            return encodedNode
        }.joined(separator: ",")
    }
    // Serializes failure output across the concurrently executed test nodes.
    @MainActor
    internal func interpretNodeTestOutput(
        _ programResult: Result<ProgramOutput, Error>,
        nodeName: String,
        multiNodeTest: MultiNodeTest,
        settings: MultiNodeTestSettings,
        runResult: RunResult
    ) throws -> InterpretedRunResult {
        print()
        print(String(repeating: "-", count: 120))
        print("[multi-node] [\(nodeName)](\(multiNodeTest.fullTestName)) Captured logs:")
        defer {
            print(String(repeating: "=", count: 120))
        }
        if multiNodeTest.crashRegex == nil,
            let result = self.interpretRegularOutput(
                programResult,
                nodeName: nodeName,
                testName: multiNodeTest.testName,
                settings: settings
            ) {
            return result
        }
        guard let expectedFailureRegex = multiNodeTest.crashRegex else {
            return .unexpectedRunResult(runResult)
        }
        guard case .signal(Int(SIGILL)) = runResult else {
            return .unexpectedRunResult(runResult)
        }
        let result: ProgramOutput = try programResult.get()
        let outputLines: [String] = result.logs
        let outputJoined: String = outputLines.joined(separator: "\n")
        if outputJoined.range(of: expectedFailureRegex, options: .regularExpression) != nil {
            if settings.dumpNodeLogs == .always {
                for line in outputLines {
                    log("[\(nodeName)](\(multiNodeTest.testName)) \(line)")
                }
            }
            return .crashedAsExpected
        }
        for line in outputLines {
            log("[\(nodeName)](\(multiNodeTest.testName)) \(line)")
        }
        return .crashRegexDidNotMatch(regex: expectedFailureRegex, output: outputJoined)
    }
    private func interpretRegularOutput(
        _ programResult: Result<ProgramOutput, Error>,
        nodeName: String,
        testName: String,
        settings: MultiNodeTestSettings
    ) -> InterpretedRunResult? {
        switch programResult {
        case .failure(let error as MultiNodeProgramError):
            var detectedReason: InterpretedRunResult?
            for line in error.completeOutput {
                log("[\(nodeName)](\(testName)) \(line)")
                if line.contains("Fatal error: "), detectedReason == nil {
                    detectedReason = .outputError(line)
                } else if case .outputError(let reasonLines) = detectedReason {
                    detectedReason = .outputError("\(reasonLines)\n\(line)")
                }
            }
            return detectedReason

        case .success(let result):
            if settings.dumpNodeLogs == .always {
                for line in result.logs {
                    log("[\(nodeName)](\(testName)) \(line)")
                }
            }
            return result.expectedExit ? .crashedAsExpected : .passedAsExpected

        default:
            return nil
        }
    }
}
