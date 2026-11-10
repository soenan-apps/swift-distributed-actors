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

import CDistributedActorsMailbox
import Dispatch
import Logging
import Metrics

import struct NIO.ByteBuffer

/// INTERNAL API: Only for use by the actor system itself
@usableFromInline
internal protocol ReceivesSystemMessages: Codable {
    var id: ActorID { get }
    var path: ActorPath { get }

    /// INTERNAL API causing an immediate send of a system message to target actor.
    /// System messages are given stronger delivery guarantees in a distributed setting than "user" messages.
    func sendSystemMessage(_ message: SystemMessages, file: String, line: UInt)

    /// INTERNAL API: This way remoting sends messages
    ///
    /// - Reminder: DO NOT use this to deliver messages from the network, deserialization and delivery,
    ///   must be performed in "one go" by `deserializeDeliver`.
    func tellOrDeadLetter(_ message: Any, file: String, line: UInt)

    // INTERNAL API
    func dropAsDeadLetter(_ message: Any, file: String, line: UInt)

    /// INTERNAL API: This way remoting sends messages
    func deserializeDeliver(
        _ messageBytes: Serialization.Buffer,
        using manifest: Serialization.Manifest,
        on pool: SerializationPool,
        file: String,
        line: UInt
    )

    /// INTERNAL API
    func unsafeGetRemotePersonality<M: Codable>(_ type: M.Type) -> RemoteClusterActorPersonality<M>
}

extension ReceivesSystemMessages {
    @usableFromInline internal var path: ActorPath {
        self.id.path
    }
}
