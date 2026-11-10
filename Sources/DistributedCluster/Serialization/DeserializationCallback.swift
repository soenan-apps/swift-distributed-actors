// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import NIO

/// Allows to "box" another value.
@usableFromInline
internal final class DeserializationCallback {
    /// A message deserialization may either be successful or fail due to attempting to deliver at an already dead
    /// actor,
    /// if this happens, we do not *statically* have the right `Message`  to cast to and the only remaining thing for
    /// such
    /// message is to be delivered as a dead letter thus we can avoid the cast entirely.
    ///
    /// Note: resolving a dead actor yields `ActorRef<Never>` thus we would _never_ be able to deliver the message to
    /// it,
    /// and have to special case the dead letter delivery.
    @usableFromInline
    internal enum DeserializedMessage {
        case deadLetter(Any)
        case message(Any)
    }

    @usableFromInline internal let call: (Result<DeserializedMessage, Error>) -> Void

    internal init(_ callback: @escaping (Result<DeserializedMessage, Error>) -> Void) {
        self.call = callback
    }
}
