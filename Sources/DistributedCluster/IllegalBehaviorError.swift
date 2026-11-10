// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

internal enum IllegalBehaviorError<Message: Codable>: Error {
    /// Not all behavior transitions are legal and can't be prevented statically.
    /// Example:
    /// Returning `.same` directly from `.setup`, such as `.setup { _ in return .same }`, is illegal because
    /// it has a high potential for eagerly looping forever during behavior canonicalization.
    /// If such behavior is indeed what you want, you can return the behavior containing the setup rather than the
    /// `.same` marker.
    case illegalTransition(from: Behavior<Message>, target: Behavior<Message>)
    /// Some behaviors, like `.same` and `.unhandled` are not allowed to be used as initial behaviors.
    /// See their individual documentation for the rationale why that is so.
    case notAllowedAsInitial(_ behavior: Behavior<Message>)

    /// Too deeply nested deferred behaviors (such a .setup) are not supported,
    /// and are often an indication of programming errors - e.g. infinitely infinitely
    /// growing behavior depth may be a mistake of accidentally needlessly wrapping behaviors with decorators they
    /// already contained.
    ///
    /// While technically it would be possible to support very very deep behaviors, in practice those are rare and Swift
    /// Distributed Actors
    /// currently opts to eagerly fail for those situations. If you have a legitimate need for such deeply nested
    /// deferred behaviors,
    /// please do not hesitate to open a ticket.
    case tooDeeplyNestedBehavior(reached: Behavior<Message>, depth: Int)

}
