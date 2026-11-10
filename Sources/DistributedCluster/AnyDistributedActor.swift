// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed

@usableFromInline
internal struct AnyDistributedActor: Sendable, Hashable {
    @usableFromInline internal let underlying: any DistributedActor

    @usableFromInline internal let id: ActorID

    @usableFromInline internal let actorSystem: ClusterSystem

    @usableFromInline
    internal init<Act: DistributedActor>(_ actor: Act) where Act.ActorSystem == ClusterSystem {
        self.underlying = actor
        self.id = actor.id
        self.actorSystem = actor.actorSystem
    }

    @usableFromInline
    internal static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    @usableFromInline
    internal func hash(into hasher: inout Hasher) {
        self.id.hash(into: &hasher)
    }
}
