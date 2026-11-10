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
import Logging

/// Allows implementing downing strategies, without having to re-implement and reinvent logging and subscription logic.
///
/// Downing strategies can focus on inspecting the membership and issuing timers if needed.
public protocol DowningStrategy {
    /// Invoked whenever the cluster emits an event.
    ///
    /// - Parameter event: cluster event that just occurred
    /// - Returns: directive, instructing the cluster to take some specific action.
    /// - Throws: If unable to handle the event for some reason; the failure will be logged and ignored.
    func onClusterEvent(event: Cluster.Event) throws -> DowningStrategyDirective

    /// Returns the action to take when a member's timeout expires.
    func onTimeout(_ member: Cluster.Member) -> DowningStrategyDirective
}
