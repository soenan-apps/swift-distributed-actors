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

/// INTERNAL API: HERE BE DRAGONS.
///
/// A "cell" containing the real actor as well as its mailbox.
///
/// Outside interactions with the actor in the cell are only permitted by sending it messages via the mailbox.
///
/// ### De-initialization
///
/// The order in which deinit's happen to the behaviors, shell, cell and mailbox are all well defined,
/// and are such that a stopped actor can be released as soon as possible (shell), yet the cell remains
/// active while anyone still holds references to it. The mailbox class on the other hand, is kept alive by
/// by the cell, as it may result in message sends to dead letters which the mailbox handles
public final class ActorCell<Message: Codable>: CustomDebugStringConvertible {
    internal let mailbox: Mailbox<Message>

    internal weak var actor: ActorShell<Message>?
    internal weak var actorSystem: ClusterSystem?

    internal var system: ClusterSystem? {
        self.actorSystem
    }

    internal var deadLetters: ActorRef<DeadLetter> {
        self.mailbox.deadLetters
    }

    internal var id: ActorID {
        self.mailbox.id
    }
    public var debugDescription: String {
        "ActorCell(\(self.id), mailbox: \(self.mailbox), actor: \(String(describing: self.actor)))"
    }

    internal init(id _: ActorID, actor: ActorShell<Message>, mailbox: Mailbox<Message>) {
        self.actorSystem = actor.system
        self.actor = actor
        self.mailbox = mailbox
    }
    @usableFromInline
    internal func sendMessage(_ message: Message, file: String = #filePath, line: UInt = #line) {
        traceLog_Mailbox(self.id.path, "sendMessage: [\(message)], to: \(self)")
        self.mailbox.sendMessage(envelope: Payload(payload: .message(message)), file: file, line: line)
    }

    internal func sendSystemMessage(_ message: SystemMessages, file: String = #filePath, line: UInt = #line) {
        traceLog_Mailbox(
            self.id.path,
            "sendSystemMessage: [\(message)], to: \(String(describing: self))"
        )
        self.mailbox.sendSystemMessage(message, file: file, line: line)
    }

    @usableFromInline
    internal func sendClosure(_ operation: @escaping () throws -> Void, file: String = #filePath, line: UInt = #line) {
        traceLog_Mailbox(self.id.path, "sendClosure from \(file):\(line) to: \(self)")
        let carry: ActorClosureCarry = ActorClosureCarry(function: operation, file: file, line: line)
        self.mailbox.sendMessage(envelope: Payload(payload: .closure(carry)), file: file, line: line)
    }

    @usableFromInline
    internal func sendSubMessage<SubMessage>(
        _ message: SubMessage,
        identifier: AnySubReceiveId,
        subReceiveAddress: ActorID,
        file: String = #filePath,
        line: UInt = #line
    ) {
        traceLog_Mailbox(self.id.path, "sendSubMessage from \(file):\(line) to: \(self)")
        let carry: SubMessageCarry = SubMessageCarry(
            identifier: identifier,
            message: message,
            subReceiveAddress: subReceiveAddress
        )
        self.mailbox.sendMessage(envelope: Payload(payload: .subMessage(carry)), file: file, line: line)
    }

    @usableFromInline
    internal func sendAdaptedMessage(_ message: Any, file: String = #filePath, line: UInt = #line) {
        traceLog_Mailbox(
            self.id.path,
            "sendAdaptedMessage from \(file):\(line) to: \(self)"
        )
        let carry: AdaptedMessageCarry = AdaptedMessageCarry(message: message)
        self.mailbox.sendMessage(envelope: Payload(payload: .adaptedMessage(carry)), file: file, line: line)
    }
}
