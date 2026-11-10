// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Noop InternalActorTransportInstrumentation

internal struct NoopActorTransportInstrumentation: InternalActorTransportInstrumentation {
    internal func remoteActorMessageSerializeStart(id _: AnyObject, recipient _: ActorPath, message _: Any) {
        // Instrumentation is disabled for this provider.
    }

    internal func remoteActorMessageSerializeEnd(id _: AnyObject, bytes _: Int) {
        // Instrumentation is disabled for this provider.
    }

    internal func remoteActorMessageDeserializeStart(id _: AnyObject, recipient _: ActorPath, bytes _: Int) {
        // Instrumentation is disabled for this provider.
    }

    internal func remoteActorMessageDeserializeEnd(id _: AnyObject, message _: Any?) {
        // Instrumentation is disabled for this provider.
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: InternalActorTransportInstrumentation

/// Receives transport serialization and deserialization lifecycle events.
public protocol InternalActorTransportInstrumentation {
    // recipient address, not just path
    /// Marks the beginning of serializing a message for a remote recipient.
    func remoteActorMessageSerializeStart(id: AnyObject, recipient: ActorPath, message: Any)
    /// Records the number of bytes produced by serialization.
    func remoteActorMessageSerializeEnd(id: AnyObject, bytes: Int)
    // func remoteActorMessageSerializeFailed

    /// Marks the beginning of decoding a received remote message.
    func remoteActorMessageDeserializeStart(id: AnyObject, recipient: ActorPath, bytes: Int)
    /// Completes decoding, with nil indicating that no message was produced.
    func remoteActorMessageDeserializeEnd(id: AnyObject, message: Any?)
    // func remoteActorMessageDeserializeEndFailed
}
