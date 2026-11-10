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

import AsyncAlgorithms
import CoreMetrics
import Distributed
import Logging
import OrderedCollections

extension OpLogDistributedReceptionist {
    internal func ensureDelayedListingFlush(of key: AnyDistributedReceptionKey) {
        if self.storage.registrations(forKey: key).isEmpty {
            self.log.debug("notify now, no need to schedule delayed flush")
            self.notifySubscribers(of: key)
            return  // no need to schedule, there are no registered actors at all, we eagerly emit this info
        }

        let timerTaskKey: Int = key.hashValue
        guard self.flushTimerTasks[timerTaskKey] == nil else {
            self.log.trace("Delayed listing flush timer task already exists (key: \(key))")
            return  // timer exists nothing to do
        }

        let flushDelay: Duration = actorSystem.settings.receptionist.listingFlushDelay
        self.log.debug("schedule delayed flush")
        self.flushTimerTasks[timerTaskKey] = Task { [weak self] in
            try await self?.whenLocal { myself in
                defer { myself.flushTimerTasks.removeValue(forKey: timerTaskKey) }

                try await Task.sleep(until: .now + flushDelay, clock: .continuous)
                myself.onDelayedListingFlushTick(key: key)
            }
        }
    }

    internal func onDelayedListingFlushTick(key: AnyDistributedReceptionKey) {
        self.log.trace("Run delayed listing flush, key: \(key)")
        self.notifySubscribers(of: key)
    }

    internal func notifySubscribers(of key: AnyDistributedReceptionKey) {
        let subscriptions: Set<DistributedListingSubscription> = self.storage.subscriptions(forKey: key)
        guard !subscriptions.isEmpty else {
            self.log.debug("No one is listening for key \(key)")
            return  // ok, no-one to notify
        }

        // Sort registrations by version from oldest to newest so that they are processed in order.
        // Otherwise, if we process a newer version (i.e., with bigger sequence number) first, older
        // versions will be dropped because they are considered "seen".
        let registrations: [VersionedRegistration] = self.storage.registrations(forKey: key)
            .sorted { older, newer in
                older.version < newer.version
            }
        self.log.notice(
            "Registrations to flush: \(registrations.count)",
            metadata: [
                "registrations": Logger.MetadataValue.array(
                    registrations.map { Logger.MetadataValue.string("\($0)") }
                ),
            ]
        )

        for subscription in subscriptions {
            self.log.notice(
                "Offering registrations to subscription: \(subscription))",
                metadata: [
                    "registrations": "\(subscription.seenActorRegistrations)"
                ]
            )

            for registration in registrations {
                if subscription.tryOffer(registration: registration) {
                    self.log.notice("OFFERED \(registration.actorID) TO \(subscription)")
                } else {
                    self.log.notice("DROPPED \(registration.actorID) TO \(subscription)")
                }
            }
        }
    }
}
