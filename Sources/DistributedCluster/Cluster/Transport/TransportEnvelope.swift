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

/// Mirrors `Envelope` however ensures that the payload is a message; i.e. it cannot be a closure.
internal struct TransportEnvelope: CustomStringConvertible, CustomDebugStringConvertible {

    internal enum Storage {
        /// Note: MAY contain SystemMessageEnvelope
        case message(Any)
        // ~~ outbound ~~
        case invocation(InvocationMessage)
        case systemMessage(SystemMessages)
        // ~~ inbound only ~~
        case systemMessageEnvelope(SystemMessageEnvelope)
        case systemMessageDelivery(SystemMessageDelivery)
    }

    internal enum SystemMessageDelivery {
        case ack(SystemMessages.ACK)
        case nack(SystemMessages.NACK)
    }

    internal let storage: Storage
    internal let recipient: ActorID

    /// Unwraps *ONE* layer of envelope
    ///
    /// I.e. if this envelope contained the system envelope -- the system envelope will be returned,
    /// for other messages, the actual message is returned.
    internal var underlyingMessage: Any {
        switch self.storage {
        case .message(let message):
            return message

        case .invocation(let invocation):
            return invocation

        case .systemMessage(let message):
            return message

        case .systemMessageEnvelope(let systemEnvelope):
            return systemEnvelope

        case .systemMessageDelivery(.ack(let ack)):
            return ack

        case .systemMessageDelivery(.nack(let nack)):
            return nack
        }
    }

    internal var description: String {
        "TransportEnvelope(\(storage), recipient: \(String(reflecting: recipient)))"
    }

    internal var debugDescription: String {
        "TransportEnvelope(_storage: \(storage), recipient: \(String(reflecting: recipient)))"
    }

    internal init(envelope: Payload, recipient: ActorID) {
        switch envelope.payload {
        case .message(let message):
            self.storage = .message(message)

        case .closure:
            fatalError(
                "Attempted to send .closure to remote actor, this is illegal and can not be made to work. "
                    + "Envelope: \(envelope), recipient: \(recipient)"
            )

        case .adaptedMessage:
            fatalError(
                "Attempted to send .adaptedMessage to remote actor, this is illegal and can not be made to work. "
                    + "Envelope: \(envelope), recipient: \(recipient)"
            )

        case .subMessage:
            fatalError(
                "Attempted to send .subMessage to remote actor, this is illegal and can not be made to work. "
                    + "Envelope: \(envelope), recipient: \(recipient)"
            )
        }
        self.recipient = recipient

    }

    internal init<Message>(message: Message, recipient: ActorID) {
        // assert(Message.self != Any.self)
        self.storage = .message(message)
        self.recipient = recipient
    }

    internal init(invocation: InvocationMessage, recipient: ActorID) {
        self.storage = .invocation(invocation)
        self.recipient = recipient
    }

    internal init(systemMessage: SystemMessages, recipient: ActorID) {
        self.storage = .systemMessage(systemMessage)
        self.recipient = recipient
    }

    internal init(systemMessageEnvelope: SystemMessageEnvelope, recipient: ActorID) {
        self.storage = .systemMessageEnvelope(systemMessageEnvelope)
        self.recipient = recipient
    }

    internal init(ack: SystemMessages.ACK, recipient: ActorID) {
        self.storage = .systemMessageDelivery(.ack(ack))
        self.recipient = recipient
    }

    internal init(nack: SystemMessages.NACK, recipient: ActorID) {
        self.storage = .systemMessageDelivery(.nack(nack))
        self.recipient = recipient
    }

}
