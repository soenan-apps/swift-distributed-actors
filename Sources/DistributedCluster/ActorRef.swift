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

/// Represents a reference to an actor.
/// All communication between actors is handled _through_ actor refs, which guarantee their isolation remains intact.
public struct ActorRef<Message: Codable>:
    @unchecked Sendable, ReceivesMessages, DeathWatchable, ReceivesSystemMessages, CustomStringConvertible, Hashable {
    /// INTERNAL API: May change without further notice.
    /// The actor ref is "aware" whether it represents a local, remote or otherwise special actor.
    ///
    /// Adj. self-conscious: feeling undue awareness of oneself, one's appearance, or one's actions.
    internal enum Personality {
        case adapter(AbstractAdapter)
        case cell(ActorCell<Message>)
        case deadLetters(DeadLetterOffice)
        case delegate(CellDelegate<Message>)
        case guardian(Guardian)
        case remote(RemoteClusterActorPersonality<Message>)

        internal static func == (lhs: ActorRef.Personality, rhs: ActorRef.Personality) -> Bool {
            switch (lhs, rhs) {
            case let (.cell(left), .cell(right)):
                return left.id == right.id

            case let (.remote(left), .remote(right)):
                return left.id == right.id

            case let (.adapter(left), .adapter(right)):
                return left.id == right.id

            case let (.guardian(left), .guardian(right)):
                return left.id == right.id

            case let (.delegate(left), .delegate(right)):
                return left.id == right.id

            case (.deadLetters, .deadLetters):
                return true

            case (.cell, _), (.remote, _), (.adapter, _), (.guardian, _), (.delegate, _), (.deadLetters, _):
                return false
            }
        }
    }

    internal let personality: Personality
    /// Address of the actor referred to by this `ActorRef`.
    public var id: ActorID {
        switch self.personality {
        case .cell(let cell):
            return cell.id

        case .remote(let remote):
            return remote.id

        case .adapter(let adapter):
            return adapter.id

        case .guardian(let guardian):
            return guardian.id

        case .delegate(let delegate):
            return delegate.id

        case .deadLetters(let letters):
            return letters.id
        }
    }
    /// Exposes given the current actor reference as limited capability representation of itself; an
    /// `AddressableActorRef`.
    ///
    /// An `AddressableActorRef` can be used to uniquely identify an actor, however it is not possible to directly send
    /// messages to such identified actor via this reference type.
    ///
    /// - SeeAlso: `AddressableActorRef` for a detailed discussion of its typical use-cases.
    public var asAddressable: AddressableActorRef {
        AddressableActorRef(self)
    }
    public var description: String {
        // we do this in order to print `Fork.Messages` rather than `SampleDiningPhilosophers.Fork.Messages`
        // or the `Messages` which a simple "\(Message.self)" would yield.
        let prettyTypeName: String = String(reflecting: Message.self)
            .split(separator: ".").dropFirst().joined(separator: ".")
        return "_ActorRef<\(prettyTypeName)>(\(self.id))"
    }
    internal var deadLettersRef: ActorRef<DeadLetter> {
        switch self.personality {
        case .cell(let cell):
            return cell.mailbox.deadLetters

        case .remote(let remote):
            return remote.system.deadLetters

        case .adapter(let adapter):
            return adapter.deadLetters

        case .deadLetters(let office):
            return .init(.deadLetters(office))

        case .delegate(let delegate):
            return delegate.system.deadLetters

        case .guardian(let guardian):
            return guardian.deadLetters
        }
    }
    @usableFromInline internal var actorSystem: ClusterSystem? {
        switch self.personality {
        case .cell(let cell):
            return cell.system

        case .adapter(let adapter):
            return adapter.system

        case .guardian(let guardian):
            return guardian.system

        case .deadLetters(let deadLetters):
            return deadLetters.system

        case .delegate(let delegate):
            return delegate.system

        case .remote(let remote):
            return remote.system
        }
    }
    /// INTERNAL API: May change without further notice.
    internal init(_ personality: Personality) {
        self.personality = personality
    }
    public static func == (lhs: ActorRef<Message>, rhs: ActorRef<Message>) -> Bool {
        lhs.id == rhs.id
    }
    /// Asynchronously "tell" the referred to actor about the `Message`.
    ///
    /// If the actor is terminating or terminated, the message will be dropped.
    ///
    /// This method is thread-safe, and may be used by multiple threads to send messages concurrently.
    /// No ordering guarantees are made about the order of the messages written by those multiple threads,
    /// in respect to each other however.
    public func tell(_ message: Message, file: String = #filePath, line: UInt = #line) {
        switch self.personality {
        case .cell(let cell):
            //            if ("\(message)".contains("handshakeWith(")) {
            //                pprint("send = \(message)", file: file, line: line)
            //            }
            cell.sendMessage(message, file: file, line: line)

        case .remote(let remote):
            remote.sendUserMessage(message, file: file, line: line)

        case .adapter(let adapter):
            adapter.trySendUserMessage(message, file: file, line: line)

        case .guardian(let guardian):
            guardian.trySendUserMessage(message, file: file, line: line)

        case .delegate(let delegate):
            delegate.sendMessage(message, file: file, line: line)

        case .deadLetters(let deadLetters):
            deadLetters.deliver(message, file: file, line: line)  // drop message directly into dead letters
        }
    }
    public func hash(into hasher: inout Hasher) {
        self.id.hash(into: &hasher)
    }
    @usableFromInline
    internal func sendSystemMessage(_ message: SystemMessages, file: String = #filePath, line: UInt = #line) {
        switch self.personality {
        case .cell(let cell):
            cell.sendSystemMessage(message, file: file, line: line)

        case .remote(let remote):
            remote.sendSystemMessage(message, file: file, line: line)

        case .adapter(let adapter):
            adapter.sendSystemMessage(message, file: file, line: line)

        case .guardian(let guardian):
            guardian.sendSystemMessage(message, file: file, line: line)

        case .delegate(let delegate):
            delegate.sendSystemMessage(message, file: file, line: line)

        case .deadLetters(let dead):
            dead.deliver(
                DeadLetter(message, recipient: self.id, sentAtFile: file, sentAtLine: line),
                file: file,
                line: line
            )
        }
    }
    public func tellOrDeadLetter(_ message: Any, file: String = #filePath, line: UInt = #line) {
        guard let typedMessage = message as? Message else {
            traceLog_Mailbox(
                self.path,
                """
                tellOrDeadLetter: [\(message)] failed because of invalid message type, to: \(self); \
                Sent at \(file):\(line)
                """
            )
            self.dropAsDeadLetter(message, file: file, line: line)
            return
        }

        self.tell(typedMessage, file: file, line: line)
    }

    public func dropAsDeadLetter(_ message: Any, file: String = #filePath, line: UInt = #line) {
        self.deadLettersRef.tell(
            DeadLetter(message, recipient: self.id, sentAtFile: file, sentAtLine: line),
            file: file,
            line: line
        )
    }

    public func deserializeDeliver(
        _ messageBytes: Serialization.Buffer,
        using manifest: Serialization.Manifest,
        on pool: SerializationPool,
        file: String = #filePath,
        line: UInt = #line
    ) {
        let deserializationStartTime: DispatchTime?
        if self.unwrapActorMetrics.active.contains(.deserialization) {
            deserializationStartTime = DispatchTime.now()
        } else {
            deserializationStartTime = nil
        }

        pool.deserializeAny(
            from: messageBytes,
            using: manifest,
            recipientPath: self.path,
            callback: .init { result in
                let metrics: ActiveActorMetrics = unwrapActorMetrics
                if metrics.active.contains(.deserialization) {
                    metrics[gauge: .deserializationSize]?.record(messageBytes.count)
                    metrics[timer: .deserializationTime]?.recordInterval(since: deserializationStartTime)
                }

                switch result {
                case .success(.message(let message)):
                    switch personality {
                    case .adapter(let adapter):
                        adapter.trySendUserMessage(message, file: file, line: line)

                    default:
                        tellOrDeadLetter(message, file: file, line: line)
                    }

                case .success(.deadLetter(let message)):
                    dropAsDeadLetter(message, file: file, line: line)

                case .failure(let error):
                    let metadata: Logger.Metadata = [
                        "recipient": "\(path)",
                        "message/expected/type": "\(String(reflecting: Message.self))",
                        "message/manifest": "\(manifest)",
                    ]

                    if let system = actorSystem {
                        system.log.warning(
                            "Failed to deserialize/deliver message to \(path), error: \(error)",
                            metadata: metadata
                        )
                    } else {

                        print("Failed to deserialize/delivery message to \(path). Metadata: \(metadata)")
                    }
                }
            }
        )
    }

    public func unsafeGetRemotePersonality<M: Codable>(_ type: M.Type = M.self) -> RemoteClusterActorPersonality<M> {
        switch self.personality {
        case .remote(let personality):
            return personality.unsafeAssumeCast(to: type)

        default:
            fatalError("Wrongly assumed personality of \(self) to be [remote]!")
        }
    }
}
