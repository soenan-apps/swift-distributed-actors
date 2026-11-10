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

import Foundation  // String.replacingOccurrences ...
import Logging

internal protocol ReceptionistOperations: BaseReceptionistOperations {
    var system: ClusterSystem { get }
}

extension ReceptionistOperations {
    @inlinable
    @discardableResult
    internal func register<Guest>(
        _ guest: Guest,
        as id: String,
        replyTo: ActorRef<Reception.Registered<Guest>>? = nil
    ) -> Reception.Key<Guest> where Guest: ReceptionistGuest {
        self.register(guest, with: .init(Guest.self, id: id), replyTo: replyTo)
    }

    @inlinable
    @discardableResult
    internal func register<Guest>(
        _ guest: Guest,
        with key: Reception.Key<Guest>,
        replyTo: ActorRef<Reception.Registered<Guest>>? = nil
    ) -> Reception.Key<Guest> where Guest: ReceptionistGuest {
        self.system.actorRefReceptionist.register(guest, with: key, replyTo: replyTo)
    }

    @inlinable
    internal func subscribe<Guest>(
        _ subscriber: ActorRef<Reception.Listing<Guest>>,
        to key: Reception.Key<Guest>
    ) where Guest: ReceptionistGuest {
        self.system.actorRefReceptionist.subscribe(subscriber, to: key)
    }

    @inlinable
    internal func lookup<Guest>(
        _ key: Reception.Key<Guest>,
        replyTo: ActorRef<Reception.Listing<Guest>>,
        timeout: Duration = .effectivelyInfinite
    ) where Guest: ReceptionistGuest {
        self.system.actorRefReceptionist.lookup(key, replyTo: replyTo, timeout: timeout)
    }
}
