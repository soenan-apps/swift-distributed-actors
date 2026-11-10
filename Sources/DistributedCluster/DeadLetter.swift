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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Dead letter

internal protocol SilentDeadLetter {}

/// A "dead letter" is a message ("letter") that is impossible to deliver to its designated recipient.
///
/// Often the reason for this is that the message was sent to given actor while it was still alive,
/// yet once it arrived the destination node the actor had already terminated, leaving the message to be dropped.
///
/// Since such races can happen when a distributed remote actor is e.g. passivated before it receives a remote call,
/// and can be tricky to diagnose otherwise, such messages are  such messages are not silently dropped,
/// but rather logged, with as much information as available (e.g. about the sender or source location of the initiating
/// tell),
/// such that when operating the system, bugs regarding undelivered messages can be spotted and fixed.
///
/// ## Not all dead letters are problems
/// No, some dead letters may happen in a perfectly healthy system and if one knows that a message could arrive
/// "too late" or be dropped for some other reason, one may mark it using the "dont log me as dead letter" protocol.
///
/// ### Trivia
/// The term dead letters, or rather "dead letter office" originates from the postal system, where undeliverable
/// mail would be called such, and shipped to one specific place to deal with these letters.
///
/// - SeeAlso: [Dead letter office](https://en.wikipedia.org/wiki/Dead_letter_office) on Wikipedia.
public struct DeadLetter: NotActuallyCodableMessage {
    internal let message: Any
    internal let recipient: ActorID?

    // sender and other metadata

    internal let sentAtFile: String?
    internal let sentAtLine: UInt?

    /// 配送できなかったメッセージと、送信元・宛先の情報を保持する。
    public init(_ message: Any, recipient: ActorID?, sentAtFile: String? = #filePath, sentAtLine: UInt? = #line) {
        self.message = message
        self.recipient = recipient
        self.sentAtFile = sentAtFile
        self.sentAtLine = sentAtLine
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: ClusterSystem.deadLetters

extension ClusterSystem {
    /// Anonymous `/dead/letters` reference, which may be used for messages which have no logical recipient.
    public var deadLetters: ActorRef<DeadLetter> {
        self.deadLettersRef
    }

    /// Dead letters reference dedicated to a specific address.
    public func personalDeadLetters<Message: Codable>(
        recipient: ActorID,
        type _: Message.Type = Message.self
    ) -> ActorRef<Message> {
        // rather could we send messages to self.deadLettersRef with enough info so it handles properly?

        guard recipient.node == self.settings.bindNode else {
            // A reference known to point at a down remote node retains its original path.
            return ActorRef(.deadLetters(.init(self.log, id: recipient, system: self))).adapt(from: Message.self)
        }

        let localRecipient: ActorID
        if recipient.path.segments.first == ActorPath.dead.segments.first {
            // drop the node from the address; and we know the pointed at ref is already dead; do not prefix it again
            localRecipient = ActorID(
                local: self.settings.bindNode,
                path: recipient.path,
                incarnation: recipient.incarnation
            )
        } else {
            // drop the node from the address; and prepend it as known-to-be-dead
            localRecipient = ActorID(
                local: self.settings.bindNode,
                path: ActorPath.dead.appending(segments: recipient.segments),
                incarnation: recipient.incarnation
            )
        }
        return ActorRef(.deadLetters(.init(self.log, id: localRecipient, system: self))).adapt(from: Message.self)
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Paths

extension ActorPath {
    internal static let dead: ActorPath = ActorPath.root.appending(segment: .deadRoot)
    internal static let deadLettersRef: ActorPath = ActorPath.dead.appending(segment: .deadLetters)
}
