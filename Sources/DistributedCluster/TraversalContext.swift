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

/// INTERNAL API: May change without any prior notice.
internal struct TraversalContext<T> {
    internal var depth: Int
    internal var accumulated: [T]
    // Remaining path segments to select; an empty slice selects the current reference.
    internal var selectorSegments: ArraySlice<ActorPathSegment>

    internal var result: TraversalResult<T> {
        if self.accumulated.count > 1 {
            return .results(self.accumulated)
        }
        switch self.accumulated.first {
        case let .some(value):
            return .result(value)

        case .none:
            return .completed
        }
    }

    internal var deeper: TraversalContext<T> {
        self.deeper(by: 1)
    }

    internal init(depth: Int, accumulated: [T], selectorSegments: [ActorPathSegment]) {
        self.depth = depth
        self.accumulated = accumulated
        self.selectorSegments = selectorSegments[...]
    }

    internal init(depth: Int, accumulated: [T], remainingSelectorSegments: ArraySlice<ActorPathSegment>) {
        self.depth = depth
        self.accumulated = accumulated
        self.selectorSegments = remainingSelectorSegments
    }

    internal init() {
        self.init(depth: -1, accumulated: [], selectorSegments: [])
    }
    /// Returns copy of traversal context yet "one level deeper"
    internal func deeper(by levels: Int) -> TraversalContext<T> {
        Self(
            depth: self.depth + levels,
            accumulated: self.accumulated,
            remainingSelectorSegments: self.selectorSegments.dropFirst()
        )
    }
}
