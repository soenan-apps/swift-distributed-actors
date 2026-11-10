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

/// Timeout configuration for automatically downing unreachable members.
public struct TimeoutBasedDowningStrategySettings {
    /// Uses a one-second delay before marking an unreachable member down.
    public static var `default`: Self {
        .init()
    }

    /// Delay between detecting unreachability and declaring a member down.
    public var downUnreachableMembersAfter: Duration = .seconds(1)
}
