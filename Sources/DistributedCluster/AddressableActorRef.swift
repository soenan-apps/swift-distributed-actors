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

import struct NIO.ByteBuffer
import protocol NIO.EventLoop

/// Represents an actor which we know existed at some point in time and this represents its type-erased reference.
///
/// An `AddressableActorRef` can be used as type-eraser for specific actor references (be it `Actor` or `ActorRef`
/// based),
/// as they may still be compared with the `AddressableActorRef` by comparing their respective addressable.
///
/// This enables an `AddressableActorRef` to be useful for watching, storing and comparing actor references of
/// various types with another.
/// Note that unlike a plain `ActorID` an `AddressableActorRef` still DOES hold an actual reference to the pointed
/// to actor,
/// even though it is not able to send messages to it (due to the lack of type-safety when doing so).
public struct AddressableActorRef: DeathWatchable, Hashable, CustomStringConvertible, ReceivesSystemMessages {
    @usableFromInline
    internal enum RefType {
        case local
        case remote

        internal var isLocal: Bool {
            self == .local
        }

        internal var isRemote: Bool {
            self == .remote
        }
    }

    internal let ref: ReceivesSystemMessages

    @usableFromInline internal let messageTypeId: ObjectIdentifier
    @usableFromInline internal let refType: RefType
    public var id: ActorID {
        self.ref.id
    }

    public var asAddressable: Self {
        self
    }
    public var description: String {
        "_AddressableActorRef(\(self.ref.id))"
    }

    public init<M>(_ ref: ActorRef<M>) {
        self.ref = ref
        self.messageTypeId = ObjectIdentifier(M.self)
        switch ref.personality {
        case .remote:
            self.refType = .remote

        default:
            self.refType = .local
        }
    }
    /// Compares unique actor identities.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    /// Hashes the unique actor identity.
    public func hash(into hasher: inout Hasher) {
        self.id.hash(into: &hasher)
    }
    internal func asReceivesSystemMessages() -> ReceivesSystemMessages {
        self.ref
    }

    internal func isRemote() -> Bool {
        switch self.refType {
        case .remote:
            return true

        case .local:
            return false
        }
    }

    @usableFromInline
    internal func sendSystemMessage(_ message: SystemMessages, file: String = #filePath, line: UInt = #line) {
        self.ref.sendSystemMessage(message, file: file, line: line)
    }
    public func tellOrDeadLetter(_ message: Any, file: String = #filePath, line: UInt = #line) {
        self.ref.tellOrDeadLetter(message, file: file, line: line)
    }

    public func dropAsDeadLetter(_ message: Any, file: String = #filePath, line: UInt = #line) {
        self.ref.dropAsDeadLetter(message, file: file, line: line)
    }

    public func deserializeDeliver(
        _ messageBytes: Serialization.Buffer,
        using manifest: Serialization.Manifest,
        on pool: SerializationPool,
        file: String = #filePath,
        line: UInt = #line
    ) {
        self.ref.deserializeDeliver(messageBytes, using: manifest, on: pool, file: file, line: line)
    }

    public func unsafeGetRemotePersonality<M: Codable>(_: M.Type = M.self) -> RemoteClusterActorPersonality<M> {
        self.ref.unsafeGetRemotePersonality(M.self)
    }
}
