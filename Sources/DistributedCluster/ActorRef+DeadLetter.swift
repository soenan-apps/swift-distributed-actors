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

import CDistributedActorsMailbox
import Dispatch
import Logging
import Metrics

import struct NIO.ByteBuffer

extension ActorRef where Message == DeadLetter {
    /// Simplified `adapt` method for dead letters, since it is known how the adaptation function looks like.
    public func adapt<IncomingMessage>(from _: IncomingMessage.Type) -> ActorRef<IncomingMessage> {
        let adapter: AbstractAdapter = DeadLetterAdapterPersonality(self.deadLettersRef, deadRecipient: self.id)
        return .init(.adapter(adapter))
    }

    /// Simplified `adapt` method for dead letters, which can be used in contexts where the adapted type can be
    /// inferred from context
    public func adapted<IncomingMessage>() -> ActorRef<IncomingMessage> {
        self.adapt(from: IncomingMessage.self)
    }
}
