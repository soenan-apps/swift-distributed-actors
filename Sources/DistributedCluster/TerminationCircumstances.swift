// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

/// The circumstances under which a child actor terminated.
@usableFromInline
internal enum TerminationCircumstances {
    /// Escalates the failure to the parent, taking precedence over a watched failure.
    case escalating(Supervision.Failure)
    /// The actor failed during message processing.
    case failed(Supervision.Failure)
    /// The actor stopped naturally by becoming stopped.
    case stopped
}
