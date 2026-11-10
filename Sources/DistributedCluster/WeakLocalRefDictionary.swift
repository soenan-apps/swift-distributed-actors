// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

import Distributed

/// A dictionary that retains local actors weakly and remote actor references strongly.
public struct WeakLocalRefDictionary<Act: DistributedActor>: ExpressibleByDictionaryLiteral
where Act.ID == ClusterSystem.ActorID {
    internal var underlying: [ClusterSystem.ActorID: WeakLocalRef<Act>]

    /// Initialize an empty dictionary.
    public init() {
        self.underlying = [:]
    }

    public init(dictionaryLiteral elements: (Act.ID, Act)...) {
        self.underlying = [:]
        self.underlying.reserveCapacity(elements.count)
        for (id, actor) in elements {
            self.underlying[id] = .init(actor)
        }
    }

    /// Inserts an actor without extending a local actor's lifetime.
    public mutating func insert(_ actor: Act) {
        self.underlying[actor.id] = WeakLocalRef(actor)
    }

    public mutating func getActor(identifiedBy id: ClusterSystem.ActorID) -> Act? {
        guard let container = underlying[id] else {
            return nil
        }

        guard let knownActor = container.actor else {
            _ = self.removeActor(identifiedBy: id)
            return nil
        }

        return knownActor
    }

    public mutating func removeActor(identifiedBy id: ClusterSystem.ActorID) -> Act? {
        self.underlying.removeValue(forKey: id)?.actor
    }
}
