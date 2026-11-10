// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO
import NIOSSL
import ServiceDiscovery
import SWIM

import class Foundation.ProcessInfo

/// Settings which allow customizing logging behavior by various sub-systems of the cluster system.
///
public struct LoggingSettings {
    /// システム初期化時の既定のlogger設定。
    public static var `default`: Self {
        .init()
    }

    /// Customize the default log level of the `system.log` (and `context.log`) loggers.
    ///
    /// This this modifies the current "base" logger which is `LoggingSettings.logger`,
    /// it is also possible to change the logger itself, e.g. if you care about reusing a specific logger
    /// or need to pass metadata through all loggers in the actor system.
    public var logLevel: Logger.Level {
        get {
            self.loggerStorage.logLevel
        }
        set {
            self.loggerStorage.logLevel = newValue
        }
    }

    /// "Base" logger that will be used as template for all loggers created by the system.
    ///
    /// Do not use this logger directly, but rather use `system.log` or  `Logger(actor:)`,
    /// as they have more useful metadata configured on them which is obtained during cluster
    /// initialization.
    ///
    /// This may be used to configure specific systems to log to specific files,
    /// or to carry system-wide metadata throughout all loggers the actor system will use.
    public var baseLogger: Logger {
        get {
            self.loggerStorage
        }
        set {
            self.customizedLogger = true
            self.loggerStorage = newValue
        }
    }

    internal var customizedLogger: Bool = false
    // Replaced by the system-specific logger during startup.
    internal var loggerStorage: Logger = Logger(label: "ClusterSystem-initializing")

    internal var useBuiltInFormatter: Bool = true

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Verbose logging of sub-systems (again, would not be needed with configurable appenders)

    /// Log all detailed timer start/cancel events
    internal var verboseTimers: Bool = false

    /// Log all actor creation events (`assignID`, `actorReady`)
    internal var verboseSpawning: Bool = false

    internal var verboseResolve: Bool = false
}
