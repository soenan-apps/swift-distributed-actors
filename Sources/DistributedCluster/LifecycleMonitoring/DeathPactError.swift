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

import Dispatch
import Distributed
import Logging
import NIO

/// Death pact error is thrown when a watched behavior actor terminates,
/// and we do not handle the termination, triggering the "death pact"
/// which is "when the watched actor terminates, I terminate".
internal enum DeathPactError: Error {
    case unhandledDeathPact(ActorID, myself: AddressableActorRef, message: String)
    case unhandledDeathPactError(ClusterSystem.ActorID, myself: ClusterSystem.ActorID, message: String)
}
