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
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

/// Contains helper functions for testing Actor based code.
/// Due to their asynchronous nature Actors are sometimes tricky to write assertions for,
/// since all communication is asynchronous and no access to internal state is offered.
///
/// The `ActorTestKit` offers a number of helpers such as test probes and helper functions to
/// make testing actor based "from the outside" code manageable and pleasant.
public final class ActorTestKit {
    @TaskLocal internal static var repeatableContextCounter: Int = 0

    /// Actor system used to spawn probes and resolve actors.
    public let system: ClusterSystem

    internal let makeProbesLock: Lock = Lock()
    /// Access should be protected by `makeProbesLock`, in order to guarantee unique names.
    internal var namingContext: ActorNamingContext = ActorNamingContext()

    /// Assertion timeouts configured for this kit.
    public let settings: ActorTestKitSettings

    /// Creates a kit and applies the supplied assertion settings.
    public init(
        _ system: ClusterSystem,
        configuredWith configureSettings: (inout ActorTestKitSettings) -> Void = { _ in () }
    ) {
        self.system = system

        var configuredSettings: ActorTestKitSettings = ActorTestKitSettings()
        configureSettings(&configuredSettings)
        self.settings = configuredSettings
    }

    internal static func withRepeatableContext<T>(body: () async throws -> T) async rethrows -> T {
        let currentRepeatableContextCounter: Int = Self.repeatableContextCounter
        return try await Self.$repeatableContextCounter.withValue(currentRepeatableContextCounter + 1) {
            try await body()
        }
    }

    internal static func withRepeatableContext<T>(body: () throws -> T) rethrows -> T {
        let currentRepeatableContextCounter: Int = Self.repeatableContextCounter
        return try Self.$repeatableContextCounter.withValue(currentRepeatableContextCounter + 1) {
            try body()
        }
    }

    // Returns `true` if we are currently executing a code clock that repeatedly
    // checks conditions. Used in `ActorTestProbe.expectX` and `ActorTestKit.error`
    // to avoid failing the test on the first iteration in e.g. an
    // `ActorTestKit.eventually` block.
    internal static func isInRepeatableContext() -> Bool {
        Self.repeatableContextCounter > 0
    }
}
