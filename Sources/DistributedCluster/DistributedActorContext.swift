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

/// Per-actor lifecycle, metadata, and call interception state owned by the actor system.
///
/// Access is limited to the owning actor and to `resignID` after that actor has terminated.
public final class DistributedActorContext {
    internal let lifecycle: LifecycleWatchContainer?
    internal let metadata: ActorMetadata
    internal let remoteCallInterceptor: (any RemoteCallInterceptor)?

    internal init(
        lifecycle: LifecycleWatchContainer?,
        remoteCallInterceptor: RemoteCallInterceptor?,
        metadata: ActorMetadata? = nil
    ) {
        self.lifecycle = lifecycle
        self.remoteCallInterceptor = remoteCallInterceptor
        self.metadata = metadata ?? ActorMetadata()

        traceLog_DeathWatch(
            "Create context; Lifecycle: \(String(describing: lifecycle))",
            file: #fileID,
            line: #line
        )
    }

    /// Invoked by the actor system when the owning actor is terminating, so we can clean up all stored data
    internal func terminate() {
        if let lifecycle {
            traceLog_DeathWatch("Terminate: \(lifecycle.watcherID)", file: #fileID, line: #line)
            lifecycle.clear()
        }
    }
}
