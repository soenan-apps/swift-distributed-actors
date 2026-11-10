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

/// Adapts actor-context registration and subscription to the system receptionist.
internal struct ActorContextReceptionist<Message: Codable>: MyselfReceptionistOperations {
    internal typealias Myself = ActorRef<Message>

    internal let underlyingContext: ActorContext<Message>

    internal var myself: Myself {
        self.underlyingContext.myself
    }

    internal var system: ClusterSystem {
        self.underlyingContext.system
    }

    internal init(context: ActorContext<Message>) {
        self.underlyingContext = context
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: ActorContext<Message> specific convenience functions

    /// Subscribe to changes in checked-in actors under given `key` by with a subReceive.
    ///
    /// The sub receive (created using `context.subReceive`) is always executed on the actor's context and thus it
    /// is
    /// thread-safe to mutate any of the actors state from this callback.
    @inlinable
    internal func subscribeMyself<Guest>(
        to key: Reception.Key<Guest>,
        subReceive: @escaping (Reception.Listing<Guest>) -> Void
    ) where Guest: ReceptionistGuest {
        let ref: ActorRef<Reception.Listing<Guest>> = self.underlyingContext.subReceive(
            Reception.Listing<Guest>.self,
            subReceive
        )
        self.system.actorRefReceptionist.subscribe(ref, to: key)
    }
}

extension ActorContext {
    /// Offers actor-isolated registration and listing callbacks.
    internal var receptionist: ActorContextReceptionist<Message> {
        ActorContextReceptionist(context: self)
    }
}
