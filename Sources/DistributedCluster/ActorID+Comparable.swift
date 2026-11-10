// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

/// Offers arbitrary ordering for predictable ordered printing of things keyed by addresses.
extension ActorID: Comparable {
    public static func < (lhs: ActorID, rhs: ActorID) -> Bool {
        lhs.node < rhs.node
            || (lhs.node == rhs.node && lhs.path < rhs.path)
            || (lhs.node == rhs.node && lhs.path == rhs.path && lhs.incarnation < rhs.incarnation)
    }
}
