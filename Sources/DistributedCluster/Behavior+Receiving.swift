// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Behavior {
    /// Defines a behavior that will be executed with an incoming message by its hosting actor.
    /// Additionally exposes `ActorContext` which can be used to e.g. log messages, spawn child actors etc.
    ///
    /// - SeeAlso: `receiveMessage` convenience behavior for when you do not need to access the `ActorContext`.
    public static func receive(
        _ handle: @escaping (ActorContext<Message>, Message) throws -> Behavior<Message>
    ) -> Behavior {
        Behavior(underlying: .receive(handle))
    }

    /// Defines a behavior that will be executed with an incoming message by its hosting actor.
    ///
    /// - SeeAlso: `receive` convenience if you also need to access the `ActorContext`.
    public static func receiveMessage(_ handle: @escaping (Message) throws -> Behavior<Message>) -> Behavior {
        Behavior(underlying: .receiveMessage(handle))
    }
}
