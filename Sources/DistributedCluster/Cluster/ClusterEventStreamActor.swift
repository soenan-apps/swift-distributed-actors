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

internal distributed actor ClusterEventStreamActor: LifecycleWatch {
    internal typealias ActorSystem = ClusterSystem

    // We maintain a snapshot i.e. the "latest version of the membership",
    // in order to eagerly publish it to anyone who subscribes immediately,
    // followed by joining them to the subsequent ``Cluster/Event`` publishes.
    //
    // Thanks to this, any subscriber immediately gets a pretty recent view of the membership,
    // followed by the usual updates via events. Since all events are published through this
    // event stream actor, all subscribers are guaranteed to see events in the right order,
    // and not miss any information as long as they apply all events they receive.
    private var snapshot: Cluster.Membership = Cluster.Membership.empty

    private var subscribers: [ActorID: ActorRef<Cluster.Event>] = [:]
    private var asyncSubscribers: [ObjectIdentifier: (Cluster.Event) -> Void] = [:]

    private lazy var log: Logger = Logger(actor: self)

    internal init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    internal static func props(customName: String?) -> Props {
        var properties: Props = Props()
        properties.knownActorName = customName ?? "clusterEventStream"
        properties.systemActor = true
        properties.wellKnown = true
        return properties
    }

    internal func subscribe(_ ref: ActorRef<Cluster.Event>) {
        self.subscribers[ref.id] = ref
        self.log.trace("Successfully subscribed [\(ref)], offering membership snapshot")
        ref.tell(.snapshot(self.snapshot))
    }

    internal func unsubscribe(_ ref: ActorRef<Cluster.Event>) {
        if self.subscribers.removeValue(forKey: ref.id) != nil {
            self.log.trace("Successfully unsubscribed [\(ref)]")
        } else {
            self.log.warning("Received `.unsubscribe` for non-subscriber [\(ref)]")
        }
    }

    internal func subscribe(_ identifier: ObjectIdentifier, eventHandler: @escaping (Cluster.Event) -> Void) {
        self.asyncSubscribers[identifier] = eventHandler
        self.log.trace("Successfully added async subscriber [\(identifier)], offering membership snapshot")
        eventHandler(.snapshot(self.snapshot))
    }

    internal func unsubscribe(_ identifier: ObjectIdentifier) {
        if self.asyncSubscribers.removeValue(forKey: identifier) != nil {
            self.log.trace("Successfully removed async subscriber [\(identifier)]")
        } else {
            self.log.warning("Received async `.unsubscribe` for non-subscriber [\(identifier)]")
        }
    }

    internal func publish(_ event: Cluster.Event) {
        do {
            try self.snapshot.apply(event: event)

            for subscriber in self.subscribers.values {
                subscriber.tell(event)
            }
            for subscriber in self.asyncSubscribers.values {
                subscriber(event)
            }

            self.log.trace(
                """
                Published event \(event) to \(self.subscribers.count) subscribers and \
                \(self.asyncSubscribers.count) async subscribers
                """,
                metadata: [
                    "eventStream/event": .string("\(reflecting: event)"),
                    "eventStream/subscribers": Logger.MetadataValue.array(
                        self.subscribers.map { subscriber in
                            Logger.MetadataValue.stringConvertible(subscriber.key)
                        }
                    ),
                    "eventStream/asyncSubscribers": Logger.MetadataValue.array(
                        self.asyncSubscribers.map { subscriber in
                            Logger.MetadataValue.stringConvertible("\(subscriber.key)")
                        }
                    ),
                ]
            )
        } catch {
            self.log.error("Failed to apply [\(event)], error: \(error)")
        }
    }

    internal func terminated(actor id: ActorID) {
        if self.subscribers.removeValue(forKey: id) != nil {
            self.log.trace("Removed subscriber [\(id)], because it terminated")
        }
    }
}
