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

/// Forwards local cluster events to subscribers, starting each subscription with a membership snapshot.
/// Events are not buffered for disconnected subscribers or redelivered.
public struct ClusterEventStream: AsyncSequence {
    public typealias Element = Cluster.Event

    /// Iterates the snapshot and subsequent events for one local subscription.
    public class AsyncIterator: AsyncIteratorProtocol {
        internal var underlying: AsyncStream<Cluster.Event>.Iterator

        internal init(_ eventStream: ClusterEventStream) {
            let (stream, continuation): (
                AsyncStream<Cluster.Event>, AsyncStream<Cluster.Event>.Continuation
            ) = AsyncStream.makeStream(of: Cluster.Event.self)
            self.underlying = stream.makeAsyncIterator()
            let identifier: ObjectIdentifier = ObjectIdentifier(self)
            Task {
                await eventStream.subscribe(identifier) { event in
                    continuation.yield(event)
                }
            }
            continuation.onTermination = { _ in
                Task {
                    await eventStream.unsubscribe(identifier)
                }
            }
        }

        /// Returns the next snapshot or cluster event, or nil after termination.
        public func next() async -> Cluster.Event? {
            await self.underlying.next()
        }
    }

    private let actor: ClusterEventStreamActor?

    internal init(_ system: ClusterSystem, customName: String? = nil) {
        let properties: Props = ClusterEventStreamActor.props(customName: customName)
        self.actor = Props.$forSpawn.withValue(properties) {
            ClusterEventStreamActor(actorSystem: system)
        }
    }

    // A detached stream is used by state-machine tests that do not publish events.
    internal init() {
        self.actor = nil
    }

    /// Creates an independent local event subscription.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(self)
    }

    nonisolated internal func subscribe(_ ref: ActorRef<Cluster.Event>) {
        Task {
            await subscribeAndWait(ref)
        }
    }

    internal func subscribeAndWait(_ ref: ActorRef<Cluster.Event>) async {
        guard let actor = self.actor else {
            return
        }
        await actor.whenLocal { localActor in
            localActor.subscribe(ref)
        }
    }

    nonisolated internal func unsubscribe(_ ref: ActorRef<Cluster.Event>) {
        Task {
            await unsubscribeAndWait(ref)
        }
    }

    internal func unsubscribeAndWait(_ ref: ActorRef<Cluster.Event>) async {
        guard let actor = self.actor else {
            return
        }
        await actor.whenLocal { localActor in
            localActor.unsubscribe(ref)
        }
    }

    private func subscribe(_ identifier: ObjectIdentifier, eventHandler: @escaping (Cluster.Event) -> Void) async {
        guard let actor = self.actor else {
            return
        }
        await actor.whenLocal { localActor in
            localActor.subscribe(identifier, eventHandler: eventHandler)
        }
    }

    private func unsubscribe(_ identifier: ObjectIdentifier) async {
        guard let actor = self.actor else {
            return
        }
        await actor.whenLocal { localActor in
            localActor.unsubscribe(identifier)
        }
    }

    internal func publish(_ event: Cluster.Event) async {
        guard let actor = self.actor else {
            return
        }
        await actor.whenLocal { localActor in
            localActor.publish(event)
        }
    }
}
