// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Noop ReceptionistInstrumentation

internal struct NoopReceptionistInstrumentation: ReceptionistInstrumentation {

    internal func actorSubscribed(key _: AnyReceptionKey, id _: ActorID) {
        // Instrumentation is disabled for this provider.
    }

    internal func actorRegistered(key _: AnyReceptionKey, id _: ActorID) {
        // Instrumentation is disabled for this provider.
    }

    internal func actorRemoved(key _: AnyReceptionKey, id _: ActorID) {
        // Instrumentation is disabled for this provider.
    }

    internal func listingPublished(key _: AnyReceptionKey, subscribers _: Int, registrations _: Int) {
        // Instrumentation is disabled for this provider.
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: ReceptionistInstrumentation

internal protocol ReceptionistInstrumentation: Sendable {
    init()

    func actorSubscribed(key: AnyReceptionKey, id: ActorID)

    func actorRegistered(key: AnyReceptionKey, id: ActorID)
    func actorRemoved(key: AnyReceptionKey, id: ActorID)

    // lookup separately?
    func listingPublished(key: AnyReceptionKey, subscribers: Int, registrations: Int)
}
