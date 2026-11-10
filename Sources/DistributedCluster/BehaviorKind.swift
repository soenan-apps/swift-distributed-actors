// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

internal enum BehaviorKind<Message: Codable> {
    indirect case failed(behavior: Behavior<Message>, cause: Supervision.Failure)
    case ignore
    indirect case intercept(behavior: Behavior<Message>, with: Interceptor<Message>)
    indirect case orElse(first: Behavior<Message>, second: Behavior<Message>)
    case receive(_ handle: (ActorContext<Message>, Message) throws -> Behavior<Message>)
    case receiveAsync(_ handle: @Sendable (ActorContext<Message>, Message) async throws -> Behavior<Message>)
    case receiveMessage(_ handle: (Message) throws -> Behavior<Message>)
    case receiveMessageAsync(_ handle: @Sendable (Message) async throws -> Behavior<Message>)
    case same
    case setup(_ onStart: (ActorContext<Message>) throws -> Behavior<Message>)
    indirect case signalHandling(
        handleMessage: Behavior<Message>,
        handleSignal: (ActorContext<Message>, Signal) throws -> Behavior<Message>
    )
    indirect case signalHandlingAsync(
        handleMessage: Behavior<Message>,
        handleSignal: @Sendable (ActorContext<Message>, Signal) async throws -> Behavior<Message>
    )
    indirect case stop(postStop: Behavior<Message>?, reason: StopReason)
    case suspend(handler: (Result<Any, Error>) throws -> Behavior<Message>)
    indirect case suspended(
        previousBehavior: Behavior<Message>,
        handler: (Result<Any, Error>) throws -> Behavior<Message>
    )
    case unhandled
}
