// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2021 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed
import Logging

import struct Foundation.Date

@testable import DistributedCluster

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Windows)
import CRT
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Unsupported runtime")
#endif

/// Logger that prints "pretty" for showcasing the cluster nicely in sample applications.
internal struct SamplePrettyLogHandler: LogHandler {
    internal static let consoleReset: String = "\u{001B}[0;0m"
    internal static let consoleBold: String = "\u{001B}[1m"

    private let label: String

    internal var logLevel: Logger.Level = .info

    internal var metadata: Logger.Metadata = Logger.Metadata()

    // internal for testing only
    internal init(label: String) {
        self.label = label
    }

    internal static func make(label: String) -> Self {
        Self(label: label)
    }

    internal func log(event: LogEvent) {
        var metadataString: String = ""
        var nodeInfo: String = ""

        var effectiveMetadata: Logger.Metadata = (event.metadata ?? [:]).merging(self.metadata) { _, new in new }
        if let node = effectiveMetadata.removeValue(forKey: "cluster/node") {
            nodeInfo += "\(node)"
        }

        let actorLabel: String = effectiveMetadata.removeValue(forKey: "actor/path")?.description ?? ""

        if !effectiveMetadata.isEmpty {
            metadataString = "\n// metadata:\n"
            for (key, value) in effectiveMetadata.sorted(by: { $0.key < $1.key }) {
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

        let fileName: Substring = event.file.split(separator: "/").last ?? ""
        let actorInfo: String = "[\(nodeInfo)\(Self.consoleBold)\(actorLabel)\(Self.consoleReset)]"
        print(
            """
            \(self.timestamp()) \(event.level) \(actorInfo)[\(fileName):\(event.line)] \
            \(event.message)\(metadataString)
            """
        )
    }

    internal func prettyPrint(metadata: Logger.MetadataValue) -> String {
        var valueDescription: String = ""
        switch metadata {
        case .string(let string):
            valueDescription = string

        case .stringConvertible(let convertible):
            valueDescription = convertible.description

        case .array(let array):
            valueDescription = "\n  \(array.map { "\($0)" }.joined(separator: "\n  "))"

        case .dictionary(let metadata):
            for (key, value) in metadata {
                valueDescription += """
                    \(Self.consoleBold)\(key)\(Self.consoleReset): \(self.prettyPrint(metadata: value))
                    """
            }
        }

        return valueDescription
    }

    private func timestamp() -> String {
        Date.now.formatted(date: .omitted, time: .standard)
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

extension DistributedActor where Self: CustomStringConvertible {
    /// Returns the actor type and its cluster identity.
    nonisolated public var description: String {
        "\(Self.self)(\(self.id))"
    }
}
