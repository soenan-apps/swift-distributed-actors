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

import Logging
import NIO

/// Leader election allows for determining a "leader" node among members.
///
/// Leaders can be useful to reduce the overhead and number of message round trips when making
/// a decision involving many peers. For example, rather than have many actors vote on what we
/// should have for lunch, we can elect a leader of the group and have it decide today's lunch plan.
/// It may remain the leader for an extended period of time, making selecting what to have for lunch
/// always a coordination-free decision. We trust that the leader always makes this decision for us.
/// If the leader were to terminate, we could elect another one.
///
/// Implementations strategies can vary intensely and may or may not need to coordinate
/// between nodes for coming up with an election result. See the documentation of a specific
/// implementation for exact semantics and guarantees.
///
/// ### Failure detection
/// Leader election by itself does not implement detecting failures. It is only tasked to select a member
/// among the provided membership to fill the role of the leader. Failure detection is however crucial to knowing _when_
/// to trigger an election, and this is handled by `SWIM`, which may detect a node to be unreachable or down, in
/// reaction
/// to which the leader election will be run again.
///
/// ### Split-brain and multiple leaders
/// Be aware that leader election implementations often MAY want to allow for the existence of multiple leaders,
/// e.g. when a partition in the cluster occurs. This is usually beneficial to _liveness_
///
/// ### Leadership Change Cluster Event
/// If a new member is selected as leader, a ``Cluster/Event`` carrying ``Cluster/LeadershipChange`` will be emitted.
/// Other actors may subscribe to `ClusterSystem.cluster.events` in order to receive and react to such changes,
/// e.g. if an actor should only perform its duties if it is residing on the current leader node.
public protocol LeaderElection {
    /// Select a member to become a leader out of the existing `Membership`.
    ///
    /// Decisions about electing/selecting a leader may be performed asynchronously.
    mutating func runElection(context: LeaderElectionContext, membership: Cluster.Membership) -> LeaderElectionResult
}
