// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed

/// Distributed actor reference helper which avoids strongly retaining local actors,
/// in order no to accidentally extend their lifetimes. Specifically very useful
/// when designing library code which should NOT keep user-actors alive, and should
/// work with remote and local actors in the same way.
///
/// The reference is *weak* when the actor is **local**,
/// in order to not prevent the actor from being deallocated when all **other**
/// references to it are released.
///
/// The reference is *strong* when referencing a **remote** distributed actor,
/// a strong reference to a remote actor does not necessarily keep it alive,
/// however it allows keeping `weak var` references to remote distributed actors
/// without them being immediately released if they were obtained from a `resolve`
/// call for example -- as by design, no-one else will be retaining them, there
/// is a risk of always observing an immediately released reference.
///
/// Rather than relying on reference counting for remote references, utilize the
/// `LifecycleWatch/watchTermination(of:)` lifecycle monitoring method. This
/// mechanism will invoke an actors ``LifecycleWatch/actorTerminated(_:)` when
/// the remote actor has terminated and we should clean it up locally.
///
/// Generally, the pattern should be to store actor references local-weakly
/// when we "don't want to keep them alive" on behalf of the user, and at the
/// same time always use ``LifecycleMonitoring`` for handling their lifecycle -
/// regardless if the actor is local or remote, lifecycle monitoring behaves
/// in the expected way.
internal final class WeakLocalRef<Act: DistributedActor>: Hashable where Act.ID == ClusterSystem.ActorID {
    internal let id: Act.ID

    private weak var weakLocalRef: Act?
    private let strongRemoteRef: Act?

    internal var actor: Act? {
        self.strongRemoteRef ?? self.weakLocalRef
    }

    internal init(_ actor: Act) {
        if isDistributedKnownRemote(actor) {
            self.weakLocalRef = nil
            self.strongRemoteRef = actor
        } else {
            self.weakLocalRef = actor
            self.strongRemoteRef = nil
        }
        self.id = actor.id
    }

    internal init(forRemoval id: ClusterSystem.ActorID) {
        self.weakLocalRef = nil
        self.strongRemoteRef = nil
        self.id = id
    }

    internal static func == (lhs: WeakLocalRef<Act>, rhs: WeakLocalRef<Act>) -> Bool {
        if lhs === rhs {
            return true
        }
        if lhs.id != rhs.id {
            return false
        }
        return true
    }
    internal func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

@_silgen_name("swift_distributed_actor_is_remote")
internal func isDistributedKnownRemote(_ actor: AnyObject) -> Bool
