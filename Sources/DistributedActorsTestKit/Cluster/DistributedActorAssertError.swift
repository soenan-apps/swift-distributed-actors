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

import Distributed
import DistributedCluster
import XCTest

/// Throws when the supplied actor is local rather than remote.
nonisolated public func assertRemoteActor<DA: DistributedActor>(_ actor: DA) throws {
    if __isRemoteActor(actor) {
        return
    }
    throw DistributedActorAssertError.expectedRemote(actor)
}

/// Throws when the supplied actor is remote rather than local.
nonisolated public func assertLocalActor<DA: DistributedActor>(_ actor: DA) throws {
    if !__isRemoteActor(actor) {
        return
    }
    throw DistributedActorAssertError.expectedRemote(actor)
}

public enum DistributedActorAssertError: Error {
    /// The assertion required a local actor.
    case expectedLocal(any DistributedActor)
    /// The assertion required a remote actor.
    case expectedRemote(any DistributedActor)
}
