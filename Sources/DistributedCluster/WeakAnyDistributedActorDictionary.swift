// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

import Distributed

/// A heterogeneous dictionary holding distributed actors weakly.
public struct WeakAnyDistributedActorDictionary {
    internal final class WeakDistributedActorContainer {
        internal weak var actor: (any DistributedActor)?

        internal init<Act: DistributedActor>(_ actor: Act) where Act.ID == ClusterSystem.ActorID {
            self.actor = actor
        }
    }

    internal var underlying: [ClusterSystem.ActorID: WeakDistributedActorContainer]

    public init() {
        self.underlying = [:]
    }

    internal mutating func removeActor(identifiedBy id: ClusterSystem.ActorID) -> Bool {
        self.underlying.removeValue(forKey: id) != nil
    }

    internal mutating func insert<Act: DistributedActor>(actor: Act) where Act.ID == ClusterSystem.ActorID {
        self.underlying[actor.id] = .init(actor)
    }

    internal mutating func get(identifiedBy id: ClusterSystem.ActorID) -> (any DistributedActor)? {
        guard let container = underlying[id] else {
            return nil
        }

        guard let knownActor = container.actor else {
            _ = self.removeActor(identifiedBy: id)
            return nil
        }

        return knownActor
    }
}
