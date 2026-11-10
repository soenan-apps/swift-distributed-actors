// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import CoreMetrics
import Logging

extension OperationLogClusterReceptionist {
    internal func onSubscribe(context: ActorContext<Message>, message: ReceptionSubscription) {
        let boxedMessage: AnySubscribe = message.boxedSubscription
        let anyKey: AnyReceptionKey = message.erasedKey
        if self.storage.addSubscription(key: anyKey, subscription: boxedMessage) {
            self.instrumentation.actorSubscribed(key: anyKey, id: message.addressableActorRef.id)

            context.watch(message.addressableActorRef)
            context.log.trace("Subscribed \(message.addressableActorRef.id) to \(anyKey)")
            boxedMessage.replyWith(self.storage.registrations(forKey: anyKey))
        }
    }

    internal func onLookup(context _: ActorContext<Message>, message: ReceptionLookup) {
        let registrations: Set<AddressableActorRef> = self.storage.registrations(forKey: message.erasedKey)

        self.instrumentation.listingPublished(
            key: message.erasedKey,
            subscribers: 1,
            registrations: registrations.count
        )
        message.replyWith(registrations)
    }

    internal func onRegister(context: ActorContext<Message>, message: AnyReceptionRegistration) {
        let key: AnyReceptionKey = message.erasedKey.asAnyKey
        let ref: AddressableActorRef = message.addressableActorRef

        guard ref.id.isLocal || (ref.id.node == context.system.cluster.node) else {
            context.log.warning(
                """
                Actor [\(ref)] attempted to register under key [\(key)], with NOT-local receptionist! \
                Actors MUST register with their local receptionist in today's Receptionist implementation.
                """
            )
            return
        }

        if self.storage.addRegistration(key: key, ref: ref) {
            self.instrumentation.actorRegistered(key: key, id: ref.id)

            context.watch(ref)

            self.addOperation(context, .register(key: key, id: ref.id))

            context.log.debug(
                "Registered [\(ref.id)] for key [\(key)]",
                metadata: [
                    "receptionist/key": "\(key)",
                    "receptionist/registered": "\(ref.id)",
                    "receptionist/opLog/maxSeqNr": "\(self.ops.maxSeqNr)",
                ]
            )

            self.ensureDelayedListingFlush(of: key, context: context)
        }

        // ---
        // Replication of is done in periodic tics, thus we do not perform a push here.
        // ---

        message.replyRegistered()
    }

    internal func ensureDelayedListingFlush(of key: AnyReceptionKey, context: ActorContext<Message>) {
        let timerKey: TimerKey = self.flushTimerKey(key)

        if self.storage.registrations(forKey: key).isEmpty {
            self.notifySubscribers(of: key)
            return  // no need to schedule, there are no registered actors at all, we eagerly emit this info
        }

        guard !context.timers.exists(key: timerKey) else {
            return  // timer exists nothing to do
        }

        let flushDelay: Duration = context.system.settings.receptionist.listingFlushDelay
        context.timers.startSingle(key: timerKey, message: ReceptionistListingFlushTick(key: key), delay: flushDelay)
    }

    internal func onDelayedListingFlushTick(
        context: ActorContext<ReceptionistMessage>,
        message: ReceptionistListingFlushTick
    ) {
        context.log.trace("Delayed listing flush: \(message.key)")

        self.notifySubscribers(of: message.key)
    }

    internal func notifySubscribers(of key: AnyReceptionKey) {
        let registrations: Set<AddressableActorRef> = self.storage.registrations(forKey: key)

        let subscriptions: Set<AnySubscribe> = self.storage.subscriptions(forKey: key)
        guard !subscriptions.isEmpty else {
            self.instrumentation.listingPublished(key: key, subscribers: 0, registrations: registrations.count)
            return  // ok, no-one to notify
        }

        self.instrumentation.listingPublished(
            key: key,
            subscribers: subscriptions.count,
            registrations: registrations.count
        )
        for subscription in subscriptions {
            subscription.reply(registrations)
        }
    }

    internal func flushTimerKey(_ key: AnyReceptionKey) -> TimerKey {
        "flush-\(key.hashValue)"
    }
}
