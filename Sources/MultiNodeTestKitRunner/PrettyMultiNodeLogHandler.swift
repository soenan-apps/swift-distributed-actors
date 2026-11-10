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
import Foundation
import Logging
import MultiNodeTestKit

internal struct PrettyMultiNodeLogHandler: LogHandler {
    internal let nodeName: String
    internal let settings: MultiNodeTestSettings.MultiNodeLogCaptureSettings
    internal var metadata: Logging.Logger.Metadata = [:]
    internal var logLevel: Logger.Level {
        get {
            .trace
        }
        set {
            _ = newValue  // The handler always captures trace-level output.
        }
    }

    internal init(nodeName: String, settings: MultiNodeTestSettings.MultiNodeLogCaptureSettings) {
        self.nodeName = nodeName
        self.settings = settings
    }
    internal static func createFormatter() -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "y-MM-dd H:m:ss.SSSS"
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }
    internal func log(event: LogEvent) {
        for excludeGrep in self.settings.excludeGrep {
            if event.file.contains(excludeGrep) || "\(event.message)".contains(excludeGrep) {
                return
            }
        }
        let date: Date = Date()
        var metadataString: String = ""
        var actorPath: String = ""
        if var eventMetadata = event.metadata {
            if let path = eventMetadata.removeValue(forKey: "actor/path") {
                actorPath = "[\(path)]"
            }
            eventMetadata.removeValue(forKey: "label")
            if !eventMetadata.isEmpty {
                metadataString = "\n"
                for key in eventMetadata.keys.sorted() {
                    guard let value = eventMetadata[key] else {
                        preconditionFailure("Sorted metadata key must be present")
                    }
                    let valueDescription: String = self.prettyPrint(metadata: value)
                    var allString: String = "\n// \"\(key)\": \(valueDescription)"
                    if allString.contains("\n") {
                        allString = String(
                            allString.split(separator: "\n").map { valueLine in
                                if valueLine.starts(with: "// ") {
                                    return "\(valueLine)\n"
                                }
                                return "// \(valueLine)\n"
                            }.joined()
                        )
                    }
                    metadataString.append(allString)
                }
                metadataString = String(metadataString.dropLast(1))
            }
        }
        let dateStr: String = Self.createFormatter().string(from: date)
        let sourceFile: Substring = event.file.split(separator: "/").last ?? ""
        print(
            "[\(dateStr)] [\(sourceFile):\(event.line)]\(actorPath) [\(event.level)] "
                + "\(event.message)\(metadataString)"
        )
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
    internal subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }
}
