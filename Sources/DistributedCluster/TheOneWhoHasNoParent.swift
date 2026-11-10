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

// The root sentinel implements the transport protocol but rejects direct messages.
// swiftlint:disable unavailable_function
/// Represents an actor that has to exist, but does not exist in reality.
/// It steps on the outer edge of the actor system and does not abide to its rules.
///
/// Only a single instance of this "actor" exists, and it is the parent of all top level guardians.
internal struct TheOneWhoHasNoParent: ReceivesSystemMessages, CustomStringConvertible, CustomDebugStringConvertible {
    // path is breaking the rules -- it never can be empty, but this is "the one", it can do whatever it wants
    @usableFromInline internal let id: ActorID

    internal var description: String {
        "/"
    }

    internal var debugDescription: String {
        "TheOneWhoHasNoParentActorRef(path: \"/\")"
    }

    internal init(local node: Cluster.Node) {
        self.id = ActorID.localRoot(on: node)
    }

    internal func sendSystemMessage(_ message: SystemMessages, file: String = #filePath, line: UInt = #line) {
        CDistributedActorsMailbox.sact_dump_backtrace()
        fatalError(
            "The \(self.id) actor MUST NOT receive any messages. Yet received \(message); Sent at \(file):\(line)"
        )
    }

    @usableFromInline
    internal func tellOrDeadLetter(_ message: Any, file: String = #filePath, line: UInt = #line) {
        CDistributedActorsMailbox.sact_dump_backtrace()
        fatalError(
            "The \(self.id) actor MUST NOT receive any messages. Yet received \(message); Sent at \(file):\(line)"
        )
    }

    @usableFromInline
    internal func dropAsDeadLetter(_ message: Any, file: String = #filePath, line: UInt = #line) {
        CDistributedActorsMailbox.sact_dump_backtrace()
        fatalError(
            "The \(self.id) actor MUST NOT receive any messages. Yet received \(message); Sent at \(file):\(line)"
        )
    }

    @usableFromInline
    internal func deserializeDeliver(
        _: Serialization.Buffer,
        using _: Serialization.Manifest,
        on _: SerializationPool,
        file: String = #filePath,
        line: UInt = #line
    ) {
        CDistributedActorsMailbox.sact_dump_backtrace()
        fatalError(
            """
            The \(self.id) actor MUST NOT receive any messages, yet attempted \(#function); Sent \
            at \(file):\(line)
            """
        )
    }

    @usableFromInline
    internal func asHashable() -> AnyHashable {
        AnyHashable(self.id)
    }

    @usableFromInline
    internal func unsafeGetRemotePersonality<M: Codable>(_: M.Type = M.self) -> RemoteClusterActorPersonality<M> {
        CDistributedActorsMailbox.sact_dump_backtrace()
        fatalError("The \(self.id) actor MUST NOT be interacted with directly!")
    }
}
// swiftlint:enable unavailable_function
