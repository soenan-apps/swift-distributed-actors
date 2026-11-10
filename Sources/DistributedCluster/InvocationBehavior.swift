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
import Logging

import struct Foundation.Data

/// Representation of the distributed invocation in the Behavior APIs.
public struct InvocationMessage: Sendable, Codable, CustomStringConvertible {
    internal let callID: ClusterSystem.CallID
    internal let targetIdentifier: String
    internal let genericSubstitutions: [String]
    internal let arguments: [Data]

    internal var target: RemoteCallTarget {
        RemoteCallTarget(targetIdentifier)
    }

    /// Describes the invocation target, substitutions, and argument count without printing argument data.
    public var description: String {
        "InvocationMessage(callID: \(callID), target: \(target), "
            + "genericSubstitutions: \(genericSubstitutions), arguments: \(arguments.count))"
    }
}

// Legacy behavior integration for distributed actor lifecycle signals.
internal enum InvocationBehavior {
    internal static func behavior(
        instance weakInstance: WeakLocalRef<some DistributedActor>
    ) -> Behavior<InvocationMessage> {
        Behavior.setup { context in
            .receiveMessageAsync { message async -> Behavior<InvocationMessage> in
                guard weakInstance.actor != nil else {
                    context.log.warning(
                        "Received message \(message) while distributed actor instance was released! Stopping..."
                    )
                    context.system.personalDeadLetters(
                        recipient: context.id, type: InvocationMessage.self
                    ).tell(message)
                    return .stop
                }

                // `InvocationMessage`s are handled in `UserMessageHandler`
                return fatalErrorBacktrace(
                    "We don't invoke distributed actors via the behavior runtime anymore! ", file: #file, line: #line
                )
            }.receiveSignal { _, signal in

                // We received a signal, but our target actor instance was already released;
                // This should not really happen, but let's handle it by stopping the behavior.
                guard let instance = weakInstance.actor else {
                    return .stop
                }

                if let terminated = signal as? Signals.Terminated {
                    if let watcher = instance as? (any LifecycleWatch) {
                        Task {
                            await watcher.whenLocal { localWatcher in
                                localWatcher.receiveActorTerminated(id: terminated.id)
                            }
                        }

                        return .same
                    }
                }

                // Invocation behaviors don't really handle signals at all.
                // Watching is done via `LifecycleWatch`.
                return .unhandled
            }
        }
    }
}
