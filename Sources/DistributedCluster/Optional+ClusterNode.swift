// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

extension Optional: @retroactive Comparable where Wrapped == Cluster.Node {
    public static func < (lhs: Cluster.Node?, rhs: Cluster.Node?) -> Bool {
        switch (lhs, rhs) {
        case (.some, .none):
            return false

        case (.none, .some):
            return true

        case let (.some(left), .some(right)):
            return left < right

        case (.none, .none):
            return false
        }
    }
}
