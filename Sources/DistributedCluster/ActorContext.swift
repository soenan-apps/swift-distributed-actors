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

import Foundation
import Logging

/// The `ActorContext` exposes an actors details and capabilities, such as names and timers.
///
/// - Warning:
///   - It MUST only ever be accessed from its own Actor. It is fine though to close over it in the actors behaviours.
///   - It MUST NOT be shared to other actors, and MUST NOT be accessed concurrently (e.g. from outside the actor).
public class ActorContext<Message: Codable> {  // NOTSendable
    /// Reference type for messages accepted by the current actor.
    public typealias Myself = ActorRef<Message>

    /// Returns `ClusterSystem` which this context belongs to.
    public var system: ClusterSystem {
        undefined()
    }

    /// Uniquely identifies this actor in the cluster.
    public var id: ActorID {
        undefined()
    }

    /// Local path under which this actor resides within the actor tree.
    public var path: ActorPath {
        undefined()
    }

    /// Last segment of the actor's path; `$` names are reserved for system actors.
    public var name: String {
        undefined()
    }

    /// Reference to this actor, stable across restarts but not across replacement at the same path.
    public var myself: ActorRef<Message> {
        undefined()
    }

    /// Provides context metadata aware `Logger`
    public var log: Logger {
        get {
            undefined()
        }
        // swiftlint:disable:next unused_setter_value
        set {
            fatalError("ActorContext.log setter must be overridden by the concrete actor context")
        }
    }

    /// `Props` which were used when spawning this actor.
    public var props: Props {
        undefined()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: BehaviorTimers

    /// Allows setting up and canceling timers, bound to the lifecycle of this actor.
    public var timers: BehaviorTimers<Message> {
        undefined()
    }

    /// Spawned children indexed by name; retain direct references when repeated lookup is unnecessary.
    public var children: Children {
        get {
            undefined()
        }
        // swiftlint:disable:next unused_setter_value
        set {
            fatalError("ActorContext.children setter must be overridden by the concrete actor context")
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Internal stopChild capability (without returning Behavior.stop) for Actorables

    /// Allows setting the "next" behavior externally.
    ///
    /// Exists solely for Actorables, should not be used in the Behavior style API.
    /// MUST be invoked from inside the actor (i.e. not concurrently).
    internal func forceStop() {
        undefined()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Death Watch

    /// Watches an actor and delivers a termination signal or the optional custom message.
    @discardableResult
    public func watch<Watchee>(
        _: Watchee,
        with _: Message? = nil,
        file _: String = #filePath,
        line _: UInt = #line
    ) -> Watchee where Watchee: DeathWatchable {
        undefined()
    }

    /// Stops watching an actor.
    @discardableResult
    public func unwatch<Watchee>(
        _: Watchee,
        file _: String = #filePath,
        line _: UInt = #line
    ) -> Watchee where Watchee: DeathWatchable {
        undefined()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Child actor management

    /// Spawns a child actor with the supplied naming strategy and behavior.
    @discardableResult
    public func spawn<M>(
        _: ActorNaming,
        _: Behavior<M>,
        props _: Props = Props(),
        file _: String = #filePath,
        line _: UInt = #line
    ) throws -> ActorRef<M>
    where M: Codable {
        undefined()
    }

    /// Spawn a child actor and start watching it to get notified about termination.
    ///
    /// For a detailed explanation of the both concepts refer to the `spawn` and `watch` documentation.
    ///
    /// - SeeAlso: `spawn`
    /// - SeeAlso: `watch`
    @discardableResult
    public func spawnWatch<M>(
        _: ActorNaming,
        _: Behavior<M>,
        props _: Props = Props(),
        file _: String = #filePath,
        line _: UInt = #line
    ) throws -> ActorRef<M>
    where M: Codable {
        undefined()
    }

    /// Stops a child actor. Repeated stops and missing incarnations produce warnings.
    /// - Throws: `ActorContextError` for non-children or `myself`; return `Behavior.stop` to stop this actor.
    public func stop<M>(child _: ActorRef<M>) throws where M: Codable {
        undefined()
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Actor Suspension Mechanisms

    /// Builds a callback executed as a message on this actor, allowing access to its state.
    /// Callbacks cannot wake an actor whose user-message processing is suspended.
    @usableFromInline
    internal func makeAsynchronousCallback<T>(
        _ callback: @escaping (T) throws -> Void,
        file: String = #filePath,
        line: UInt = #line
    ) -> AsynchronousCallback<T> {
        AsynchronousCallback(callback: callback) { [weak selfRef = self.myself.unsafeUnwrapCell] closure in
            selfRef?.sendClosure(closure, file: file, line: line)
        }
    }

    /// Builds a typed callback executed as a message on this actor, allowing access to its state.
    /// Callbacks cannot wake an actor whose user-message processing is suspended.
    @usableFromInline
    internal func makeAsynchronousCallback<T>(
        for _: T.Type,
        callback: @escaping (T) throws -> Void,
        file: String = #filePath,
        line: UInt = #line
    ) -> AsynchronousCallback<T> {
        AsynchronousCallback(callback: callback) { [weak selfRef = self.myself.unsafeUnwrapCell] closure in
            selfRef?.sendClosure(closure, file: file, line: line)
        }
    }

    /// ***CAUTION***: This functionality should be used with extreme caution, as it will
    ///                stall user message processing for up to the configured timeout.
    ///
    /// While executing a suspension is non-blocking, and the actor will continue processing
    /// system messages, it does hinder the actor from processing any subsequent user messages
    /// until the `task` completes. In other words, it can cause mailbox queue buildup,
    /// if it is receiving many messages while awaiting for the completion signal.
    ///
    /// The behavior returned by the `continuation` is applied as-if it was returned in place of the
    /// returned suspension, i.e. returning .same is legal and means keeping the behavior that
    /// was current at the point where the suspension was initiated. Returning another suspending
    /// behavior is legal, and causes another suspension.
    ///
    /// - Parameters:
    ///   - AsyncResult: result of an asynchronous operation the actor is waiting for
    ///   - timeout: time after which the AsyncResult will be failed if it does not complete
    ///   - continuation: continuation to run after `AsyncResult` completes. It is safe to access
    ///                   and modify actor state from here.
    /// - Returns: a behavior that causes the actor to suspend until the `AsyncResult` completes
    internal func awaitResult<AR: AsyncResult>(
        of asyncResult: AR,
        timeout: Duration,
        _ continuation: @escaping (Result<AR.Value, Error>) throws -> Behavior<Message>
    ) -> Behavior<Message> {
        asyncResult.withTimeout(after: timeout).onComplete { [weak selfRef = self.myself.unsafeUnwrapCell] result in
            selfRef?.sendSystemMessage(.resume(result.map { $0 as Any }), file: #filePath, line: #line)
        }
        return .suspend(handler: continuation)
    }

    /// ***CAUTION***: This functionality should be used with extreme caution, as it will
    ///                stall user message processing for up to the configured timeout.
    ///
    /// Similar to `awaitResult`, however in case the suspended-on `AsyncTask` completes
    /// with a `.failure`, the behavior will escalate this failure causing the actor to
    /// crash (or be subject to supervision).
    ///
    /// - SeeAlso: `awaitResult`
    /// - Parameters:
    ///   - AsyncResult: result of an asynchronous operation the actor is waiting for
    ///   - timeout: time after which the AsyncResult will be failed if it does not complete
    ///   - continuation: continuation to run after `AsyncResult` completes. It is safe to access
    ///                   and modify actor state from here.
    /// - Returns: a behavior that causes the actor to suspend until the `AsyncResult` completes
    internal func awaitResultThrowing<AR: AsyncResult>(
        of asyncResult: AR,
        timeout: Duration,
        _ continuation: @escaping (AR.Value) throws -> Behavior<Message>
    ) -> Behavior<Message> {
        self.awaitResult(of: asyncResult, timeout: timeout) { result in
            switch result {
            case let .success(res):
                return try continuation(res)

            case let .failure(error):
                throw error
            }
        }
    }

    /// Applies the result of the `task` to the given `continuation` within the
    /// same actor context, after it completes. The returned behavior will be
    /// assigned as the new behavior of the actor. The actor will keep processing
    /// other incoming messages, while `task` has not been completed, as opposed
    /// to `awaitResult`, which suspends message processing of the actor and
    /// only allows signals to be processed.
    ///
    /// - Parameters:
    ///   - task: result of an asynchronous operation the actor is waiting for
    ///   - timeout: time after which the AsyncResult will be failed if it does not complete
    ///   - continuation: continuation to run after `AsyncResult` completes.
    ///     It is safe to access and modify actor state from here.
    internal func onResultAsync<AR: AsyncResult>(
        of asyncResult: AR,
        timeout: Duration,
        _ continuation: @escaping (Result<AR.Value, Error>) throws -> Behavior<Message>,
        file: String = #filePath,
        line: UInt = #line
    ) {
        let asyncCallback: AsynchronousCallback<Result<AR.Value, Error>> = self.makeAsynchronousCallback(
            for: Result<AR.Value, Error>.self,
            callback: { result in
                let nextBehavior: Behavior<Message> = try continuation(result)
                let shell: ActorShell<Message> = self.downcastUnsafe
                shell.behavior = try shell.behavior.canonicalize(shell, next: nextBehavior)
            },
            file: file,
            line: line
        )

        asyncResult.withTimeout(after: timeout).onComplete { res in
            asyncCallback.invoke(res)
        }
    }

    /// Applies the result of the `task` to the given `continuation` within the
    /// same actor context, after it completes. The returned behavior will be
    /// assigned as the new behavior of the actor. The actor will keep processing
    /// other incoming messages, while `task` has not been completed, as opposed
    /// to `awaitResult`, which suspends message processing of the actor and
    /// only allows signals to be processed.
    ///
    /// In case the given `AsyncTask` completes with a `.failure`, the failure
    /// will be escalated, causing the actor to crash (or be subject to supervision).
    ///
    /// - Parameters:
    ///   - task: result of an asynchronous operation the actor is waiting for
    ///   - timeout: time after which the AsyncResult will be failed if it does not complete
    ///   - continuation: continuation to run after `AsyncResult` completes. It is safe to access
    ///                   and modify actor state from here.
    internal func onResultAsyncThrowing<AR: AsyncResult>(
        of asyncResult: AR,
        timeout: Duration,
        _ continuation: @escaping (AR.Value) throws -> Behavior<Message>
    ) {
        self.onResultAsync(of: asyncResult, timeout: timeout) { res in
            switch res {
            case let .success(value):
                return try continuation(value)

            case let .failure(error):
                throw error
            }
        }
    }

    // ====
    // ----------------------------------------------------------------------------------------------------------------

    // MARK: Message Adapters & Sub-Receive

    /// Adapts this `ActorRef` to accept messages of another type by applying the conversion
    /// function. There can only be one adapter defined per type. Creating a new adapter will
    /// replace an existing adapter.
    ///
    /// The returned `ActorRef` can be watched and the lifetime is bound to that of the owning actor, meaning
    /// that when the owning actor terminates, this `ActorRef` terminates as well.
    ///
    /// ### Dropping messages
    /// It is possible to return `nil` as the result of an adaptation, which results in the message
    /// being silently dropped. This can be useful when not all messages `From` have a valid representation in
    /// `Message`, or if not all `From` messages are of interest for this particular actor.
    public final func messageAdapter<From>(_ adapt: @escaping (From) -> Message?) -> ActorRef<From>
    where From: Codable {
        self.messageAdapter(from: From.self, adapt: adapt)
    }

    /// Adapts this `ActorRef` to accept messages of another type by applying the conversion
    /// function. There can only be one adapter defined per type. Creating a new adapter will
    /// replace an existing adapter.
    ///
    /// The returned `ActorRef` can be watched and the lifetime is bound to that of the owning actor, meaning
    /// that when the owning actor terminates, this `ActorRef` terminates as well.
    ///
    /// ### Dropping messages
    /// It is possible to return `nil` as the result of an adaptation, which results in the message
    /// being silently dropped. This can be useful when not all messages `From` have a valid representation in
    /// `Message`, or if not all `From` messages are of interest for this particular actor.
    public func messageAdapter<From>(from _: From.Type, adapt _: @escaping (From) -> Message?) -> ActorRef<From>
    where From: Codable {
        undefined()
    }

    /// Creates an `ActorRef` that can receive messages of the specified type, but executed in the same
    /// context as the actor owning it, meaning that it is safe to close over mutable state internal to the
    /// surrounding actor and modify it.
    ///
    /// The returned `ActorRef` can be watched and the lifetime is bound to that of the owning actor, meaning
    /// that when the owning actor terminates, this `ActorRef` terminates as well.
    ///
    /// There can only be one `subReceive` per `SubReceiveId`. When installing a new `subReceive`
    /// with an existing `SubReceiveId`, it replaces the old one. All references will remain valid and point to
    /// the new behavior.
    public func subReceive<SubMessage>(
        _: SubReceiveId<SubMessage>,
        _: SubMessage.Type,
        _: @escaping (SubMessage) throws -> Void
    ) -> ActorRef<SubMessage>
    where SubMessage: Codable {
        undefined()
    }

    /// Creates an `ActorRef` that can receive messages of the specified type, but executed in the same
    /// context as the actor owning it, meaning that it is safe to close over mutable state internal to the
    /// surrounding actor and modify it.
    ///
    /// The returned `ActorRef` can be watched and the lifetime is bound to that of the owning actor, meaning
    /// that when the owning actor terminates, this `ActorRef` terminates as well.
    ///
    /// There can only be one `subReceive` per type. When installing a new `subReceive`
    /// with an existing type, it replaces the old one. All references will remain valid and point to
    /// the new behavior.
    public func subReceive<SubMessage>(
        _ type: SubMessage.Type,
        _ closure: @escaping (SubMessage) throws -> Void
    ) -> ActorRef<SubMessage> {
        self.subReceive(SubReceiveId(type), type, closure)
    }

    @usableFromInline
    internal func subReceive(identifiedBy _: AnySubReceiveId) -> ((SubMessageCarry) throws -> Behavior<Message>)? {
        undefined()
    }
}
