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

/// INTERNAL API: Not intended to be used by end users.
///
/// Directives that steer the traversal state machine (which, however, always remains depth-first).
internal enum TraversalDirective<T> {
    case `continue`
    case abort(Error)
    case accumulateMany([T])
    case accumulateSingle(T)
}
