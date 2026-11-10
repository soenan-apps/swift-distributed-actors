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

/// Specialized `Logger` factory, populating the logger with metadata about its "owner" actor (or system),
/// such as it's path or node on which it resides.
///
/// The preferred way of obtaining a logger for an actor or system is `context.log` or `system.log`, rather than
/// creating new ones.
extension Logger {
    /// Create a logger specific to this actor.
    public init<Act: DistributedActor>(actor: Act) where Act.ActorSystem == ClusterSystem {
        var log: Logger = actor.actorSystem.settings.logging.baseLogger
        log[metadataKey: "actor/path"] = "\(actor.id.path)"
        log[metadataKey: "actor/id"] = "\(actor.id)"
        self = log
    }

    /// Creates a logger tagged with the current actor path.
    public static func make<T>(context: ActorContext<T>) -> Logger {
        Self.make(context.log, path: context.path)
    }

    internal static func make(_ base: Logger, path: ActorPath) -> Logger {
        var log: Logger = base  // yes
        log[metadataKey: "actor/path"] = Self.MetadataValue.stringConvertible(path)
        return log
    }

    /// Allows passing in a `Logger.Level?` and not log if it was `nil`.
    @inlinable
    public func log(
        level: Logger.Level?,
        _ message: @autoclosure () -> Logger.Message,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        if let level = level {
            self.log(level: level, message(), metadata: metadata(), file: file, function: function, line: line)
        }
    }
}
