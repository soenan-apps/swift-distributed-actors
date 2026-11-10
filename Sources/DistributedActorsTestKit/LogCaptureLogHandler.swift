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

internal struct LogCaptureLogHandler: LogHandler {
    internal let label: String
    internal let capture: LogCapture
    internal var metadata: Logger.Metadata = [:]

    internal var logLevel: Logger.Level {
        get {
            self.capture.settings.minimumLogLevel
        }
        set {
            _ = newValue  // The capture uses its configured minimum level.
        }
    }

    internal init(label: String, _ capture: LogCapture) {
        self.label = label
        self.capture = capture
    }

    internal func log(event: LogEvent) {
        let actorPath: String = self.metadata["actor/path"].map { "\($0)" } ?? ""
        guard
            self.capture.settings.filterActorPaths.contains(where: { path in
                path.isEmpty || actorPath.starts(with: path)
            })
        else {
            return
        }
        guard !self.capture.settings.excludeActorPaths.contains(actorPath) else {
            return
        }
        guard
            self.capture.settings.grep.isEmpty
                || self.capture.settings.grep.contains(where: { "\(event.message)".contains($0) })
        else {
            return
        }
        guard !self.capture.settings.excludeGrep.contains(where: { "\(event.message)".contains($0) }) else {
            return
        }
        var mergedMetadata: Logger.Metadata = self.metadata
        mergedMetadata.merge(event.metadata ?? [:]) { _, incoming in incoming }
        mergedMetadata["label"] = "\(self.label)"
        self.capture.append(
            CapturedLogMessage(
                date: Date(),
                level: event.level,
                message: event.message,
                metadata: mergedMetadata,
                file: event.file,
                function: event.function,
                line: event.line
            )
        )
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
