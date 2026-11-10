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
import class Foundation.ProcessInfo
import struct Foundation.URL
import class Foundation.FileHandle

#if canImport(Darwin) || canImport(Glibc)
import class Foundation.Process
#endif

private struct RunnerUnsupportedPlatform: Error {}

private struct MultiNodeSummaryLine {
    let line: String
    let failed: Bool
}

internal struct NodeInterpretedRunResult {
    internal let node: String
    internal let result: MultiNodeTestKitRunnerBoot.InterpretedRunResult
}

#if canImport(Darwin) || canImport(Glibc)
private struct NodeProcessConfiguration {
    let binary: String
    let suite: String
    let testName: String
    let allNodes: String
    let devNull: FileHandle
    let group: any EventLoopGroup
}
#endif

extension MultiNodeTestKitRunnerBoot {
    internal struct MultiNodeTestSummary {
        private var summaryLines: [MultiNodeSummaryLine] = []

        internal var failedTests: Int {
            self.summaryLines.filter(\.failed).count
        }

        internal mutating func emit(_ message: String, failed: Bool) {
            if failed {
                return emitFailed(message)
            }

            print("[multi-node] \(message)")
            self.summaryLines.append(MultiNodeSummaryLine(line: message, failed: false))
        }

        internal mutating func emitFailed(_ message: String) {
            print("[multi-node] \(message)".red)
            self.summaryLines.append(MultiNodeSummaryLine(line: message, failed: true))
        }

        internal func dump() {
            print(String(repeating: "=", count: 120))
            print("[multi-node] MULTI NODE TEST SUITE RUN SUMMARY:")
            for line in self.summaryLines {
                print(line.line)
            }
            print(String(repeating: "=", count: 120))
        }

    }

    internal static let passedMarker: String = "\("test passed".green)"
    internal static let failedMarker: String = "\("test failed".red)"

    internal func runAndEval(suite: String, testName: String, summary: inout MultiNodeTestSummary) async {
        let startDate: Date = Date()
        summary.emit("Test '\(suite).\(testName)' started at \(startDate)", failed: false)
        do {
            guard let binary = CommandLine.arguments.first else {
                preconditionFailure("The runner command must contain its executable path")
            }
            let runResult: InterpretedRunResult = try await runMultiNodeTest(
                suite: suite,
                testName: testName,
                binary: binary
            )
            let endDate: Date = Date()
            var message: String = "Test '\(suite).\(testName)' finished: "
            var failed: Bool = false
            switch runResult {
            case .passedAsExpected:
                message += "OK (PASSED) "

            case .crashedAsExpected:
                message += "OK (EXPECTED CRASH) "

            case .crashRegexDidNotMatch(let regex, output: _):
                message += "FAILED: crash regex did not match output; regex: \(regex) "
                failed = true

            case .unexpectedRunResult(let unexpectedResult):
                summary.emitFailed("FAILED: unexpected run result: \(unexpectedResult) ")
                failed = true

            case .outputError(let description):
                message += "FAILED: \(description) "
                failed = true
            }
            summary.emit("\(message) (took: \(endDate.timeIntervalSince(startDate)))", failed: failed)
        } catch {
            let endDate: Date = Date()
            summary.emitFailed(
                "Test '\(suite).\(testName)' finished: FAILED (took: "
                    + "\(endDate.timeIntervalSince(startDate))), threw error: \(error)"
            )
        }
    }
    internal func commandTest(summary: inout MultiNodeTestSummary, filter: TestFilter) async {
        for testSuite in kMultiNodeTestSuites {
            let suiteStartDate: Date = Date()
            summary.emit("", failed: false)
            summary.emit("[multi-node] TestSuite '\(testSuite.key)' started at \(suiteStartDate)", failed: false)
            for test in allTestsForSuite(testSuite.key)
            where filter.matches(suiteName: testSuite.key, testName: test.0) {
                await runAndEval(suite: testSuite.key, testName: test.0, summary: &summary)
            }
        }
    }

    internal func runMultiNodeTest(
        suite: String,
        testName: String,
        binary: String
    ) async throws -> InterpretedRunResult {
        #if !canImport(Darwin) && !canImport(Glibc)
        throw RunnerUnsupportedPlatform()
        #else
        guard let test = self.findMultiNodeTest(suite: suite, testName: testName) else {
            throw MultiNodeTestNotFound(suite: suite, test: testName)
        }
        let devNull: FileHandle = try FileHandle(forUpdating: URL(fileURLWithPath: "/dev/null"))
        defer {
            devNull.closeFile()
        }
        var settings: MultiNodeTestSettings = MultiNodeTestSettings()
        test.configureMultiNodeTest(&settings)
        let group: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let configuration: NodeProcessConfiguration = NodeProcessConfiguration(
            binary: binary,
            suite: suite,
            testName: testName,
            allNodes: self.makeAllNodesCommandString(nodeNames: test.nodeNames, deployNodes: []),
            devNull: devNull,
            group: group
        )
        let execution: Result<[NodeInterpretedRunResult], Error>
        do {
            let results: [NodeInterpretedRunResult] = try await withThrowingTaskGroup(
                of: NodeInterpretedRunResult.self,
                returning: [NodeInterpretedRunResult].self
            ) { tasks in
                for nodeName in test.nodeNames {
                    tasks.addTask { [settings] in
                        try await self.runNode(nodeName, test: test, settings: settings, configuration: configuration)
                    }
                }
                var collectedResults: [NodeInterpretedRunResult] = []
                collectedResults.reserveCapacity(test.nodeNames.count)
                for try await result in tasks {
                    collectedResults.append(result)
                }
                return collectedResults
            }
            execution = .success(results)
        } catch {
            execution = .failure(error)
        }
        try await group.shutdownGracefully()
        return try self.summarizeNodeResults(execution.get(), suite: suite, testName: testName)
        #endif
    }

    private func summarizeNodeResults(
        _ results: [NodeInterpretedRunResult],
        suite: String,
        testName: String
    ) -> InterpretedRunResult {
        let mark: String = results.contains { $0.result.failed } ? Self.failedMarker : Self.passedMarker
        log("Test '\(suite).\(testName)' results: \(mark)")
        for test in results {
            let nodeMark: String = test.result.passed ? Self.passedMarker : Self.failedMarker
            log("[\(test.node)] [\(nodeMark)] \(test.result)")
        }
        for result in results where result.result.failed {
            return result.result
        }
        return .passedAsExpected
    }

    #if canImport(Darwin) || canImport(Glibc)
    private func runNode(
        _ nodeName: String,
        test: MultiNodeTest,
        settings: MultiNodeTestSettings,
        configuration: NodeProcessConfiguration
    ) async throws -> NodeInterpretedRunResult {
        let grepper: OutputGrepper = OutputGrepper.make(
            nodeName: nodeName,
            group: configuration.group
        )
        let output: FileHandle = grepper.processOutputPipe
        let process: Process = Process()
        process.binaryPath = configuration.binary
        process.standardInput = configuration.devNull
        process.standardOutput = output
        process.standardError = output
        process.arguments = [
            "_exec", configuration.suite, configuration.testName, nodeName, configuration.allNodes,
        ]
        try process.runProcess()
        guard let binaryPath = process.binaryPath else {
            preconditionFailure("The spawned process must have an executable path")
        }
        log(
            "[exec] \(binaryPath) \(process.arguments?.joined(separator: " ") ?? "")\n"
                + "  \(nodeName) -> PID: \(process.processIdentifier)"
        )
        assert(process.processIdentifier != 0, "Failed to spawn process")
        let reaper: Task<Void, Never> = self.startTestTimeoutReaperTask(
            nodeName: nodeName,
            process: process,
            settings: settings
        )
        process.waitUntilExit()
        reaper.cancel()
        output.closeFile()
        let result: Result<ProgramOutput, Error> = Result {
            try grepper.result.wait()
        }
        let runResult: RunResult =
            process.terminationReason == .exit
            ? .exit(Int(process.terminationStatus)) : .signal(Int(process.terminationStatus))
        let interpreted: InterpretedRunResult = try await self.interpretNodeTestOutput(
            result,
            nodeName: nodeName,
            multiNodeTest: test,
            settings: settings,
            runResult: runResult
        )
        return NodeInterpretedRunResult(node: nodeName, result: interpreted)
    }
    #endif

    #if canImport(Darwin) || canImport(Glibc)
    private func startTestTimeoutReaperTask(
        nodeName: String,
        process: Process,
        settings: MultiNodeTestSettings
    ) -> Task<Void, Never> {
        Task.detached {
            try? await Task.sleep(until: .now + settings.execRunHardTimeout, clock: .continuous)
            guard !Task.isCancelled else {
                return
            }

            print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            print("!!!!!!       MULTI-NODE TEST TEST NODE \(nodeName) SEEMS STUCK - TERMINATE     !!!!!!")
            print("!!!!!!       PID: \(ProcessInfo.processInfo.processIdentifier)                 !!!!!!")
            print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")

            process.terminate()
        }
    }
    #endif
}

internal func prettyWait(seconds: Int64, hint: String) async {
    if seconds < 1 {
        return
    }

    let messageBase: String = "[multi-node] Wait (\(hint))"

    var lastMsg: String = "\(seconds)s remaining..."
    print("\(messageBase) \(lastMsg)", terminator: "")
    for elapsed in 0..<seconds {
        try? await Task.sleep(until: .now + .seconds(1), clock: .continuous)
        lastMsg = "\(seconds - elapsed)s remaining..."
        print("\r\(messageBase) \(lastMsg)", terminator: " ")
    }
    print("\r\(messageBase) (waited \(seconds)s) GO!                            ".yellow)
}
