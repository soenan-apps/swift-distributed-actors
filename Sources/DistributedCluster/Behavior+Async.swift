// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Behavior {
    /// Defines a behavior that will be executed with an incoming message by its hosting actor.
    /// Additionally exposes `ActorContext` which can be used to e.g. log messages, spawn child actors etc.
    ///
    /// The function is asynchronous and is allowed to suspend.
    ///
    /// WARNING: Use this ONLY with 'distributed actor' which will guarantee the actor hops are correct.
    ///
    /// - SeeAlso: `receiveMessageAsync` convenience behavior for when you do not need to access the `ActorContext`.
    public static func receiveAsync(
        _ handle: @Sendable @escaping (ActorContext<Message>, Message) async throws -> Behavior<Message>
    ) -> Behavior {
        Behavior(underlying: .receiveAsync(handle))
    }

    /// Defines a behavior that will be executed with an incoming message by its hosting actor.
    ///
    ///
    /// The function is asynchronous and is allowed to suspend.
    ///
    /// WARNING: Use this ONLY with 'distributed actor' which will guarantee the actor hops are correct.
    ///
    /// - SeeAlso: `receiveAsync` convenience if you also need to access the `ActorContext`.
    public static func receiveMessageAsync(
        _ handle: @Sendable @escaping (Message) async throws -> Behavior<Message>
    ) -> Behavior {
        Behavior(underlying: .receiveMessageAsync(handle))
    }

    internal func receiveAsync0(
        _ recv: @Sendable @escaping (Message) async throws -> Behavior<Message>,
        context: ActorContext<Message>,
        message: Message
    ) -> Behavior<Message> {
        let loop: any EventLoop = context.system.eventLoopGroup.next()
        let promise: EventLoopPromise<Behavior<Message>> = loop.makePromise(of: Behavior<Message>.self)

        Task {
            do {
                let next: Behavior<Message> = try await recv(message)
                promise.succeed(next)
            } catch {
                promise.fail(error)
            }
        }

        return context.awaitResultThrowing(of: promise.futureResult, timeout: .effectivelyInfinite) { next in
            // become the "next" behavior, realistically with 'distributed actor' this is always '.same'
            next
        }
    }

    @usableFromInline
    internal func receiveAsync(
        _ recv: @Sendable @escaping (ActorContext<Message>, Message) async throws -> Behavior<Message>,
        _ message: Message
    ) -> Behavior<Message> {
        .setup { context in
            receiveAsync0(
                { nextMessage in
                    try await recv(context, nextMessage)
                },
                context: context,
                message: message
            )
        }
    }

    @usableFromInline
    internal func receiveMessageAsync(
        _ recv: @Sendable @escaping (Message) async throws -> Behavior<Message>,
        _ message: Message
    ) -> Behavior<Message> {
        .setup { context in
            receiveAsync0(recv, context: context, message: message)
        }
    }

    internal func receiveSignalAsync0(
        _ handleSignal: @Sendable @escaping (ActorContext<Message>, Signal) async throws -> Behavior<Message>,
        context _: ActorContext<Message>,
        signal: Signal
    ) -> Behavior<Message> {
        .setup { context in
            let loop: any EventLoop = context.system.eventLoopGroup.next()
            let promise: EventLoopPromise<Behavior<Message>> = loop.makePromise(of: Behavior<Message>.self)

            Task {
                do {
                    let next: Behavior<Message> = try await handleSignal(context, signal)
                    promise.succeed(next)
                } catch {
                    promise.fail(error)
                }
            }

            return context.awaitResultThrowing(of: promise.futureResult, timeout: .effectivelyInfinite) { next in
                // become the "next" behavior, realistically with 'distributed actor' this is always '.same'
                next
            }
        }
    }

    @usableFromInline
    internal func receiveSignalAsync(
        context _: ActorContext<Message>,
        signal: Signal,
        handleSignal:
            @escaping @Sendable (
                ActorContext<Message>,
                Signal
            ) async throws -> Behavior<Message>
    ) -> Behavior<Message> {
        .setup { context in
            receiveSignalAsync0(handleSignal, context: context, signal: signal)
        }
    }

}
