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

import Distributed
import DistributedActorsConcurrencyHelpers
import Foundation
import Logging

// implement logging infrastructure - pipe as messages to dedicated logging actor
internal struct ActorOriginLogHandler: LogHandler {
    private let context: LoggingContext

    private var targetLogger: Logger
    internal var logLevel: Logger.Level {
        get {
            self.targetLogger.logLevel
        }
        set {
            self.targetLogger.logLevel = newValue
        }
    }

    // This seems worse to implement since I can't pass through my "reads of lazy cause rendering"
    internal var metadata: Logger.Metadata {
        get {
            self.context.metadata
        }
        set {
            self.context.metadata = newValue
        }
    }

    internal init(_ context: LoggingContext) {
        self.context = context

        self.targetLogger = context.logger
        self.targetLogger.logLevel = self.logLevel
    }

    internal init<T>(_ context: ActorContext<T>) {
        let dispatcherName: String = context.props.dispatcher.name
        self.init(
            LoggingContext(
                logger: context.log,
                identifier: context.path.description,
                useBuiltInFormatter: context.system.settings.logging.useBuiltInFormatter,
                dispatcher: { dispatcherName }
            )
        )
    }

    internal init(_ system: ClusterSystem, identifier: String? = nil) {
        self.init(
            LoggingContext(
                logger: system.log,
                identifier: identifier ?? system.name,
                useBuiltInFormatter: system.settings.logging.useBuiltInFormatter,
                dispatcher: { currentPThreadThreadID() }
            )
        )
    }

    internal static func createFormatter() -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "y-MM-dd H:m:ss.SSSS"
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }

    internal static func createSimpleFormatter() -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "H:m:ss.SSSS"
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }

    private static func formatMessage(_ logRecord: inout LogMessage) -> String {
        let dispatcherPart: String
        if let dispatcher = logRecord.effectiveMetadata?.removeValue(forKey: "dispatcher") {
            dispatcherPart = "[\(dispatcher)]"
        } else {
            dispatcherPart = ""
        }

        let actorPathPart: String
        if let actorPath = logRecord.effectiveMetadata?.removeValue(forKey: "actor/path") {
            actorPathPart = "[\(actorPath)]"
        } else {
            actorPathPart = ""
        }

        let actorSystemIdentity: String
        if let node = logRecord.effectiveMetadata?.removeValue(forKey: "cluster/node") {
            actorSystemIdentity = "[\(node)]"
        } else {
            actorSystemIdentity = ""
        }

        var msg: String = ""
        msg += "\(actorSystemIdentity)"
        msg += "[\(logRecord.file.split(separator: "/").last ?? "<unknown-file>"):\(logRecord.line)]"
        msg += "\(dispatcherPart)"
        msg += "\(actorPathPart)"
        msg += " \(logRecord.message)"
        return msg
    }

    internal func log(event: LogEvent) {
        self.log(
            level: event.level,
            message: event.message,
            metadata: event.metadata,
            source: event.source,
            file: event.file,
            function: event.function,
            line: event.line
        )
    }

    // SwiftLog.LogHandler requires this complete signature.
    // swiftlint:disable:next function_parameter_count
    internal func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source _: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // this actually would be dispatching to the logging infra (has ticket)

        let logMessage: LogMessage = LogMessage(
            identifier: self.context.identifier,
            time: Date(),
            level: level,
            message: message,
            effectiveMetadata: self.context.effectiveMetadata(overrides: metadata),  // should force lazies
            file: file,
            function: function,
            line: line
        )

        self.invokeConfiguredLoggingInfra(logMessage)
    }

    internal func invokeConfiguredLoggingInfra(_ logMessage: LogMessage) {
        // here we can either log... or dispatch to actor... or invoke Logging. etc

        guard self.context.useBuiltInFormatter else {
            self.targetLogger.log(
                level: logMessage.level,
                logMessage.message,
                metadata: self.metadata,
                file: logMessage.file,
                function: logMessage.function,
                line: logMessage.line
            )
            return
        }

        var logRecord: LogMessage = logMessage

        var msg: String = Self.formatMessage(&logRecord)

        guard ProcessInfo.processInfo.environment["SACT_PRETTY_LOG"] != nil else {
            // no "pretty" logging
            self.targetLogger.log(
                level: logMessage.level,
                Logger.Message(stringLiteral: msg),
                metadata: logRecord.effectiveMetadata,
                file: logMessage.file,
                function: logMessage.function,
                line: logMessage.line
            )
            return
        }

        // "pretty" logging
        if let effectiveMetadata = logRecord.effectiveMetadata, !effectiveMetadata.isEmpty {
            msg += self.formatMetadata(effectiveMetadata)
        }
        self.targetLogger.log(
            level: logMessage.level,
            Logger.Message(stringLiteral: msg),
            metadata: [:],
            file: logMessage.file,
            function: logMessage.function,
            line: logMessage.line
        )
    }
    private func formatMetadata(_ metadata: Logger.Metadata) -> String {
        var metadataString: String = "\n// metadata:\n"
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) where key != "label" {
            var allString: String = "\n// \"\(key)\": \(value)"
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
        return String(metadataString.dropLast(1))
    }
    // hope to remove this one
    internal subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            self.context[metadataKey: metadataKey]
        }
        set {
            self.context[metadataKey: metadataKey] = newValue
        }
    }
}
