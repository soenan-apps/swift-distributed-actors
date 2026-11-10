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
import RegexBuilder
import XCTest

internal struct InspectActorRow {
    internal let typeName: String
    internal var count: Int
    internal var objectIDs: Set<String>

    internal func dump() {
        print(self.dumpString())
    }

    internal func dumpString() -> String {
        """
        \(self.typeName)
          - count: \(self.count)
          - ids: \(self.objectIDs)\n
        """
    }
}

internal struct InspectActorsLeakedError: Error {
    internal let message: String
    internal let before: InspectKit.ActorStats
    internal let after: InspectKit.ActorStats
}

private struct InspectUnsupportedPlatform: Error {}

internal enum InspectKit {
    internal struct ActorStats {
        internal var stats: [String: InspectActorRow] = [:]

        internal var totalCount: Int {
            var count: Int = 0
            for row in self.stats.values {
                count += row.count
            }
            return count
        }

        internal func dump() {
            for row in self.stats.values {
                row.dump()
            }
        }

        internal func dumpString() -> String {
            var description: String = ""
            for row in self.stats.values {
                description += row.dumpString()
            }
            return description
        }

        internal func detectLeaks(latest: Self) -> InspectActorsLeakedError? {
            var difference: Self = latest
            for row in self.stats.values {
                if var latestRow = latest.stats[row.typeName] {
                    latestRow.count -= row.count
                    for identifier in row.objectIDs {
                        latestRow.objectIDs.remove(identifier)
                    }
                    // This is a numeric allocation delta, not a collection count.
                    // swiftlint:disable:next empty_count
                    if latestRow.count > 0 {
                        difference.stats[row.typeName] = latestRow
                    }
                }
            }
            guard difference.totalCount > 0 else {
                return nil
            }
            var message: String = ""
            message += "!!!!!! DETECTED LEAKED ACTORS: \(difference.totalCount) !!!!\n"
            message += "BEFORE ============================================\n"
            message += self.dumpString()
            message += "NOW ===============================================\n"
            message += latest.dumpString()
            message += "DIFF ==============================================\n"
            message += difference.dumpString()
            message += "DIFF ==============================================\n"
            message += "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
            return InspectActorsLeakedError(message: message, before: self, after: latest)
        }
    }

    private static var baseDir: String {
        FileManager.default.currentDirectoryPath
    }

    /// Returns actor names and their live instance counts.
    internal static func actorStats() throws -> ActorStats {
        #if !canImport(Foundation.Process)
        throw InspectUnsupportedPlatform()
        #else
        let result: (output: [Substring], error: [Substring]) = Self.runCommand(
            cmd: "\(self.baseDir)/scripts/dump_actors.sh"
        )
        var stats: [String: InspectActorRow] = [:]
        for outputLine in result.output {
            let trimmedLine: Substring = outputLine.drop { $0 == " " }
            guard let idAndType = trimmedLine.firstMatch(of: try Regex(".*?(?= state)"))?.0 else {
                continue
            }
            let components: [Substring] = idAndType.split(separator: " ")
            guard let identifier = components.first else {
                continue
            }
            let name: String = components.dropFirst().joined(separator: " ")
            var stat: InspectActorRow = stats[name] ?? .init(typeName: name, count: 0, objectIDs: [])
            stat.count += 1
            stat.objectIDs.insert(String(identifier))
            stats[name] = stat
        }
        for errorLine in result.error {
            print("[InspectKit:error] \(errorLine)")
        }
        return ActorStats(stats: stats)
        #endif
    }

    #if canImport(Foundation.Process)
    private static func runCommand(
        cmd: String,
        args: String...
    ) -> (output: [Substring], error: [Substring]) {
        let task: Process = Process()
        task.launchPath = cmd
        task.arguments = args
        let outputPipe: Pipe = Pipe()
        task.standardOutput = outputPipe
        let errorPipe: Pipe = Pipe()
        task.standardError = errorPipe
        task.launch()
        let output: [Substring] = Self.readLines(from: outputPipe)
        let errors: [Substring] = Self.readLines(from: errorPipe)
        task.waitUntilExit()
        return (output, errors)
    }

    private static func readLines(from pipe: Pipe) -> [Substring] {
        let data: Data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let string = String(data: data, encoding: .utf8) else {
            return []
        }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
    }
    #endif
}

#if canImport(Foundation.Process)
// Compatible with Swift on all macOS versions as well as Linux.
extension Process {
    internal var binaryPath: String? {
        get {
            if #available(macOS 10.13, *) {
                return self.executableURL?.path
            } else {
                return self.launchPath
            }
        }
        set {
            if #available(macOS 10.13, *) {
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
#endif
