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

/// Instructs the downing shell to update member state or timers.
public struct DowningStrategyDirective {
    internal enum Repr {
        case cancelTimer(member: Cluster.Member)
        case markAsDown(Set<Cluster.Member>)
        case startTimer(member: Cluster.Member, delay: Duration)
        case unchanged
    }

    /// Leaves member state and timers unchanged.
    public static var unchanged: Self {
        .init(.unchanged)
    }

    internal let underlying: Repr

    internal init(_ underlying: Repr) {
        self.underlying = underlying
    }

    /// Cancels the pending timeout for a member.
    public static func cancelTimer(member: Cluster.Member) -> Self {
        .init(.cancelTimer(member: member))
    }

    /// Marks every supplied member down.
    public static func markAsDown(members: Set<Cluster.Member>) -> Self {
        .init(.markAsDown(members))
    }

    /// Marks one member down.
    public static func markAsDown(_ member: Cluster.Member) -> Self {
        .init(.markAsDown([member]))
    }

    /// Starts the member's timeout after the supplied delay.
    public static func startTimer(member: Cluster.Member, delay: Duration) -> Self {
        .init(.startTimer(member: member, delay: delay))
    }
}
