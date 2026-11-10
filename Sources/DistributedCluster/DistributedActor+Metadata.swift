// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

extension DistributedActor where ActorSystem == ClusterSystem {
    /// このActorのIDに付随するmetadata。
    nonisolated public var metadata: ActorMetadata {
        self.id.metadata
    }

    /// Provides the actor context for use within this actor.
    /// The context must not be mutated concurrently with the owning actor, however the things it stores may provide
    /// additional synchronization to make this safe.
    internal var context: DistributedActorContext {
        self.id.context
    }
}
