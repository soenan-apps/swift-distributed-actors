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

import DistributedActorsConcurrencyHelpers
import Logging
import NIO

import struct Foundation.Date

/// A bidirectional association permits ordered message exchange after a successful handshake.
internal final class Association: CustomStringConvertible, @unchecked Sendable {

    internal enum State {
        case associating(queue: MPSCLinkedQueue<TransportEnvelope>)
        case associated(channel: Channel)
        case tombstone(ActorRef<DeadLetter>)
    }
    /// A tombstone is necessary to be kept for a period of time when an association is terminated,
    /// as we may never be completely sure if the other node is truly terminated or just had network (or other issues)
    /// for some time. In the case it'd try to associate and communicate with us again, we must be able to reject it
    /// as we've terminated the association already, yet it may not have done so for its association to us.
    ///
    /// Tombstones are lighter than live associations and expire after `settings.associationTombstoneTTL`.
    internal struct Tombstone: Hashable {
        internal let remoteNode: Cluster.Node

        /// Determines when the Tombstone should be removed from kept tombstones in the ClusterShell.
        /// End of life of the tombstone is calculated as `now + settings.associationTombstoneTTL`.
        internal let removalDeadline: ContinuousClock.Instant

        internal init(_ node: Cluster.Node, settings: ClusterSystemSettings) {
            self.removalDeadline = .fromNow(settings.associationTombstoneTTL)
            self.remoteNode = node
        }

        /// Used to create "any" tombstone, for being able to lookup in Set<TombstoneSet>
        internal init(_ node: Cluster.Node) {
            self.removalDeadline = .now  // ANY value here is ok, we do not use it in hash/equals
            self.remoteNode = node
        }

        internal static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.remoteNode == rhs.remoteNode
        }

        internal func hash(into hasher: inout Hasher) {
            self.remoteNode.hash(into: &hasher)
        }
    }
    // and the only reason is really because the off chance case in which we have to make an Association earlier than we
    // have the handshake completed (i.e. we send to a ref that is not yet associated)
    internal let lock: Lock

    //       We'd prefer to have a lock-less way to implement this and we can achieve it but it's a pain to implement so
    // will be done in a separate step.
    internal var state: State

    /// Tasks to be executed when transitioning to completed/terminated state.
    private var completionTasks: [() -> Void]

    /// The address of this node, that was offered to the remote side for this association
    /// This matters in case we have multiple "self" addresses; e.g. we bind to one address, but expose another because
    /// NAT
    internal let selfNode: Cluster.Node
    internal var remoteNode: Cluster.Node

    internal var description: String {
        """
        AssociatedState(\(self.state), selfNode: \(reflecting: self.selfNode), \
        remoteNode: \(reflecting: self.remoteNode))
        """
    }
    /// Whether the handshake is still collecting pending messages.
    internal var isAssociating: Bool {
        switch self.state {
        case .associating:
            return true

        default:
            return false
        }
    }

    /// Whether the association has a live transport channel.
    internal var isAssociated: Bool {
        switch self.state {
        case .associated:
            return true

        default:
            return false
        }
    }

    /// Whether the association has been terminated.
    internal var isTombstone: Bool {
        switch self.state {
        case .tombstone:
            return true

        default:
            return false
        }
    }

    internal init(selfNode: Cluster.Node, remoteNode: Cluster.Node) {
        self.selfNode = selfNode
        self.remoteNode = remoteNode
        self.lock = Lock()
        self.state = .associating(queue: .init())
        self.completionTasks = []
    }

    /// Complete the association and drain any pending message sends onto the channel.
    internal func completeAssociation(handshake: HandshakeStateMachine.CompletedState, over channel: Channel) throws {
        assert(
            self.remoteNode == handshake.remoteNode,
            """
            Complete association with wrong node was invoked. \
            Association, remote node: \(self.remoteNode); \
            Handshake, remote node: \(handshake.remoteNode)
            """
        )

        try self.lock.withLockVoid {
            switch self.state {
            case .associating(let sendQueue):
                // 1) we need to flush all the queued up messages
                //    - yes, we need to flush while holding the lock... it's an annoyance in this lock based design
                //      but it ensures that once we've flushed, all other messages will be sent in the proper order
                // "after"
                //      the previously enqueued ones; A lockless design would not be able to get rid of the queue AFAIR,
                while let envelope = sendQueue.dequeue() {
                    _ = channel.writeAndFlush(envelope)
                }

                // 2) execute any pending tasks and clear them
                self.runCompletionTasks()

                // 3) store associated channel
                self.state = .associated(channel: channel)

            case .associated:
                let desc: String = "\(channel)"
                _ = channel.close()
                throw AssociationError.alreadyCompleted(
                    self,
                    offendingChannelDescription: desc
                )

            case .tombstone:
                let desc: String = "\(channel)"
                _ = channel.close()
                throw AssociationError.attemptToCompleteTombstonedAssociation(self, offendingChannelDescription: desc)
            }
        }
    }

    /// Sometimes, while the association is still associating, we may need to enqueue tasks to be performed after it has
    /// completed.
    /// This function ensures that once the `completeAssociation` is invoked and all messages flushed, the enqueued
    /// tasks will be executed (in same order as submitted).
    ///
    /// If the association is already associated or terminated, the task is executed immediately
    /// Implementation note: futures are unavailable here because there may be no event loop to hand work to.
    internal func enqueueCompletionTask(_ task: @escaping () -> Void) {
        self.lock.withLockVoid {
            switch self.state {
            case .associating:
                self.completionTasks.append(task)

            default:
                task()
            }
        }
    }

    /// Terminate the association and store a tombstone in it.
    ///
    /// If any messages were still queued up in it, or if it was hosting a channel these get drained / closed,
    /// before the tombstone is returned.
    ///
    /// After invoking this the association will never again be useful for sending messages.
    internal func terminate(_ system: ClusterSystem) -> Association.Tombstone {
        self.lock.withLockVoid {
            switch self.state {
            case .associating(let sendQueue):
                while let envelope = sendQueue.dequeue() {
                    system.deadLetters.tell(.init(envelope.underlyingMessage, recipient: envelope.recipient))
                }
                self.runCompletionTasks()
                // in case someone stored a reference to this association in a ref, we swap it into a dead letter sink
                self.state = .tombstone(system.deadLetters)

            case .associated(let channel):
                _ = channel.close()
                // in case someone stored a reference to this association in a ref, we swap it into a dead letter sink
                self.state = .tombstone(system.deadLetters)

            case .tombstone:
                ()  // ok
            }
        }

        return Self.Tombstone(self.remoteNode, settings: system.settings)
    }

    /// Runs and clears completion tasks.
    private func runCompletionTasks() {
        for task in self.completionTasks {
            task()
        }
        self.completionTasks = []
    }

    /// Concurrency: safe to invoke from any thread.
    internal func sendUserMessage(envelope: Payload, recipient: ActorID, promise: EventLoopPromise<Void>? = nil) {
        let transportEnvelope: TransportEnvelope = TransportEnvelope(envelope: envelope, recipient: recipient)
        self.send(transportEnvelope, promise: promise)
    }

    /// Concurrency: safe to invoke from any thread.
    internal func sendInvocation(
        _ invocation: InvocationMessage,
        recipient: ActorID,
        promise: EventLoopPromise<Void>? = nil
    ) {
        let transportEnvelope: TransportEnvelope = TransportEnvelope(invocation: invocation, recipient: recipient)
        self.send(transportEnvelope, promise: promise)
    }

    /// Concurrency: safe to invoke from any thread.
    internal func sendSystemMessage(
        _ message: SystemMessages,
        recipient: ActorID,
        promise: EventLoopPromise<Void>? = nil
    ) {
        let transportEnvelope: TransportEnvelope = TransportEnvelope(systemMessage: message, recipient: recipient)
        self.send(transportEnvelope, promise: promise)
    }

    /// Concurrency: safe to invoke from any thread.
    private func send(_ envelope: TransportEnvelope, promise: EventLoopPromise<Void>?) {
        self.lock.withLockVoid {
            switch self.state {
            case .associating(let sendQueue):
                sendQueue.enqueue(envelope)

            case .associated(let channel):
                channel.writeAndFlush(envelope, promise: promise)

            case .tombstone(let deadLetters):
                deadLetters.tell(.init(envelope.underlyingMessage, recipient: envelope.recipient))
            }
        }
    }
}
