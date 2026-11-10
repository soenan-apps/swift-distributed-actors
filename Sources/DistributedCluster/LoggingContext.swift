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

/// - Warning: NOT thread safe! Only use from Actors, properly synchronize access, or create multiple instances for each
/// execution context.
internal final class LoggingContext {
    // deprecate, we should not need this explicit type

    internal let identifier: String

    // want to eventually not have this; also move to more structured logging perhaps...
    /// If `true` the built-in "pretty" formatter should be used, rather than passing verbatim to underlying
    /// `LogHandler`
    internal let useBuiltInFormatter: Bool

    internal let logger: Logger

    @usableFromInline internal var storage: Logger.Metadata = [:]

    internal var metadata: Logger.Metadata {
        get {
            self.storage
        }
        set {
            self.storage = newValue
        }
    }

    internal init(logger: Logger, identifier: String, useBuiltInFormatter: Bool, dispatcher: (() -> String)?) {
        self.logger = logger
        self.identifier = identifier
        self.useBuiltInFormatter = useBuiltInFormatter
        if let makeDispatcherName = dispatcher {
            self.storage["dispatcher"] = .lazyString(makeDispatcherName)
        }
    }
    internal func effectiveMetadata(overrides: Logger.Metadata?) -> Logger.Metadata {
        if let overs = overrides {
            return self.storage.merging(overs) { _, replacement in replacement }
        }
        return self.storage
    }
    @inlinable
    internal subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            self.storage[metadataKey]
        }
        set {
            self.storage[metadataKey] = newValue
        }
    }
}
