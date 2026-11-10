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

import Logging

/// Configures this node's response when the cluster marks it down.
public struct OnDownActionStrategySettings {
    private enum Storage {
        case disabled
        case gracefulShutdown(delay: Duration)
    }

    /// Takes no automatic action; the application must arrange shutdown of the downed node.
    public static let disabled: OnDownActionStrategySettings = .init(.disabled)

    private let underlying: Storage

    private init(_ underlying: Storage) {
        self.underlying = underlying
    }

    /// Initiates graceful shutdown after the given delay once this node is marked down.
    public static func gracefulShutdown(delay: Duration) -> Self {
        .init(.gracefulShutdown(delay: delay))
    }

    private static func shutDown(_ system: ClusterSystem) {
        do {
            try system.shutdown()
        } catch {
            system.log.error("Failed to shut down the downed node: \(error)")
        }
    }

    internal func make() -> (ClusterSystem) throws -> Void {
        switch self.underlying {
        case .disabled:
            return { _ in () }

        case .gracefulShutdown(let shutdownDelay):
            return { system in
                try system.spawn(
                    "leaver",
                    Behavior<String>.setup { context in
                        guard .milliseconds(0) < shutdownDelay else {
                            context.log.warning(
                                """
                                This node was marked as [.down], delay is immediate. \
                                Shutting down the system immediately!
                                """
                            )
                            Task { Self.shutDown(system) }
                            return .stop
                        }

                        context.timers.startSingle(key: "shutdown-delay", message: "shutdown", delay: shutdownDelay)
                        system.log.warning(
                            """
                            This node was marked as [.down], performing OnDownAction as configured: \
                            shutting down the system, in \(shutdownDelay)
                            """
                        )

                        return .receiveMessage { _ in
                            system.log.warning("Shutting down...")
                            Task { Self.shutDown(system) }
                            return .stop
                        }
                    }
                )
            }
        }
    }
}
