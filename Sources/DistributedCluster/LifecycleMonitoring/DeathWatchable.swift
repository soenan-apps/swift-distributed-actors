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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Death Watch

/// Marks an entity to be "watchable", meaning it may participate in Death Watch and form Death Pacts.
///
/// Watchable entities are `ActorRef<>`, `Actor<>` but also actors of unknown type such as `AddressableActorRef`.
///
/// - SeeAlso: `ActorContext.watch`
/// - SeeAlso: `DeathWatch`
public protocol DeathWatchable: AddressableActor {}

extension ActorContext: DeathWatchProtocol {}
