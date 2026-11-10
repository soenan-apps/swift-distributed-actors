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

extension Cluster.Event {
    internal enum CodingKeys: String, CodingKey {
        case leadershipChange = "leadershipChange"
        case membershipChange = "membershipChange"
        case nonExhaustive = "_PLEASE_DO_NOT_EXHAUSTIVELY_MATCH_THIS_ENUM_NEW_CASES_MIGHT_BE_ADDED_IN_THE_FUTURE"
        case reachabilityChange = "reachabilityChange"
        case snapshot = "snapshot"
    }
}
