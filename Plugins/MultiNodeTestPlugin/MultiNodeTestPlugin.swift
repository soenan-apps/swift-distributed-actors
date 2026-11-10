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

import Foundation
import PackagePlugin

internal struct UsageError: Error, CustomStringConvertible {
    internal let message: String

    internal var description: String {
        self.message
    }
}

internal func log(_ log: String) {
    print("[multi-node] \(log)")
}

internal struct MultiNodeTestPluginError: Error {
    internal let message: String
    internal let file: String
    internal let line: UInt

    internal init(message: String, file: String = #file, line: UInt = #line) {
        self.message = message
        self.file = file
        self.line = line
    }
}

@main
internal final class MultiNodeTestPlugin: CommandPlugin {
    internal var buildConfiguration: PackageManager.BuildConfiguration = .release

    internal func performCommand(context _: PluginContext, arguments: [String]) throws {
        guard !arguments.isEmpty else {
            try self.usage(arguments: arguments)
        }

        if let configIdx = arguments.firstIndex(of: "-c") {
            let configValueIdx: Int = arguments.index(after: configIdx)
            if configValueIdx < arguments.endIndex {
                if arguments[configValueIdx] == "debug" {
                    self.buildConfiguration = .debug
                } else if arguments[configValueIdx] == "release" {
                    self.buildConfiguration = .release
                }
            }
        }

        let toolName: String = "MultiNodeTestKitRunner"

        // Terminate all previous runners
        Process.killall(name: toolName)

        switch self.buildConfiguration {
        case .debug:
            log("Building multi-node project for debugging...")

        case .release:
            log("Building multi-node project for production...")

        default:
            fatalError("Unknown build configuration: \(self.buildConfiguration)")
        }

        let buildResult: PackageManager.BuildResult = try packageManager.build(
            .all(includingTests: true),
            parameters: .init(configuration: self.buildConfiguration)
        )

        guard buildResult.succeeded else {
            log(buildResult.logText)
            return
        }

        guard
            let multiNodeRunner = buildResult.builtArtifacts.first(where: { artifact in
                artifact.kind == .executable && artifact.url.lastPathComponent.starts(with: toolName)
            })
        else {
            throw MultiNodeTestPluginError(message: "Failed")
        }

        log("Detected multi-node test runner: \(multiNodeRunner.url.lastPathComponent)")

        let process: Process = Process()
        let binaryPath: String = multiNodeRunner.url.path
        process.binaryPath = binaryPath
        process.arguments = arguments

        do {
            log("> \(toolName) \(process.arguments?.joined(separator: " ") ?? "")")
            try process.runProcess()
            process.waitUntilExit()
        } catch {
            log("[error] Failed to execute multi-node [\(binaryPath) \(arguments)]! Error: \(error)")
        }
    }

    internal func usage(arguments: [String]) throws -> Never {
        throw UsageError(
            message: """
                ILLEGAL INVOCATION: \(arguments)
                USAGE:
                > swift package --disable-sandbox multi-node [OPTIONS] COMMAND

                OPTIONS:
                    -c release/debug  - to build in release or debug mode (default: \(self.buildConfiguration))

                COMMAND:
                    test - run multi-node tests
                    _exec
                """
        )
    }
}

// Compatible with Swift on all macOS versions as well as Linux
extension Process {
    internal var binaryPath: String? {
        get {
            if #available(macOS 10.13, *) {  // '*' covers Linux
                return self.executableURL?.path
            } else {
                return self.launchPath
            }
        }
        set {
            if #available(macOS 10.13, *) {  // '*' covers Linux
                self.executableURL = newValue.map { URL(fileURLWithPath: $0) }
            } else {
                self.launchPath = newValue
            }
        }
    }

    internal func runProcess() throws {
        if #available(macOS 10.13, *) {
            try self.run()
        } else {
            self.launch()
        }
    }
}

extension Process {
    internal static func killall(name: String) {
        let killAllRunners: Process = Process()
        killAllRunners.binaryPath = "/usr/bin/killall"
        killAllRunners.arguments = ["-9", name]
        try? killAllRunners.runProcess()
        killAllRunners.waitUntilExit()
    }
}
