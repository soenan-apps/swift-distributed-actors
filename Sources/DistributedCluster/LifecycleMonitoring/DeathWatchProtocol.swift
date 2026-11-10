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

import Dispatch
import Distributed
import Logging
import NIO

/// Defines behavior-actor watch and unwatch operations.
public protocol DeathWatchProtocol {
    /// The watched behavior actor's message type.
    associatedtype Message: Codable

    /// Watches the given actor for termination, which means that this actor will receive a `.terminated` signal
    /// when the watched actor fails ("dies"), be it via throwing a Swift Error or performing some other kind of fault.
    ///
    /// There is no difference between keeping the passed in reference or using the returned ref from this method.
    /// The actor is the being watched subject, not a specific reference to it.
    ///
    /// Death Pact: By watching an actor one enters a so-called "death pact" with the watchee,
    /// meaning that this actor will also terminate itself once it receives the `.terminated` signal
    /// for the watchee. A simple mnemonic to remember this is to think of the Romeo & Juliet scene where
    /// the lovers each end their lives, thinking the other has died.
    ///
    /// Alternatively, one can handle the `.terminated` signal using the `.receiveSignal(Signal -> Behavior<Message>)`
    /// method,
    /// which gives this actor the ability to react to the watchee's death in some other fashion,
    /// for example by saying some nice words about its life, or spawning a "replacement" of watchee in its' place.
    ///
    /// When the `.terminated` signal is handled by this actor, the automatic death pact will not be triggered.
    /// If the `.terminated` signal is handled by returning `.unhandled` it is the same as if the signal was not handled
    /// at all,
    /// and the Death Pact will trigger as usual.
    ///
    /// ### The watch(:with:) variant
    /// Watch offers another variant of the API, which allows you to customize what message shall be received
    /// when the watchee is terminated. The message may be optionally passed as `context.watch(ref, with: MyMessage(ref,
    /// ...))`,
    /// allowing you to carry additional context "along with" the information about _which_ actor has terminated.
    /// Note that the delivery semantics of when this message is delivered is the same as `Signals.Terminated` (i.e.
    /// it's delivery is guaranteed, even in face of message loss across nodes), and the actual message is _local_
    /// (meaning
    /// that internally all signalling is still performed using `Terminated` and system messages, but when the time
    /// comes
    /// to deliver it to this actor, instead the customized message is delivered).
    ///
    /// Invoking `watch()` multiple times with differing `with` arguments results in only the _latest_ invocation to
    /// take effect.
    /// In other words, when an actor terminates, the customized termination message that was last provided "wins,"
    /// and is delivered to the watcher (this actor).
    ///
    /// # Examples:
    ///
    ///     // watch some known ActorRef<M>
    ///     context.watch(someRef)
    ///
    ///     // watch a child actor immediately when spawning it, (entering a death pact with it)
    ///     let child = try context.watch(context.spawn("child", (behavior)))
    ///
    ///     // watch(:with:)
    ///     context.watch(ref, with: .customMessageOnTermination(ref, otherInformation))
    ///
    /// #### Concurrency:
    ///  - MUST NOT be invoked concurrently to the actors execution, i.e. from the "outside" of the current actor.
    @discardableResult
    func watch<Watchee>(
        _ watchee: Watchee,
        with terminationMessage: Message?,
        file: String,
        line: UInt
    ) -> Watchee where Watchee: DeathWatchable

    /// Reverts the watching of an previously watched actor.
    ///
    /// Unwatching a not-previously-watched actor has no effect.
    ///
    /// ### Semantics for in-flight Terminated signals
    ///
    /// After invoking `unwatch`, even if a `Signals.Terminated` signal was already enqueued at this actors
    /// mailbox; this signal would NOT be delivered to the `onSignal` behavior, since the intent of no longer
    /// watching the terminating actor takes immediate effect.
    ///
    /// #### Concurrency:
    ///  - MUST NOT be invoked concurrently to the actors execution, i.e. from the "outside" of the current actor.
    ///
    /// - Returns: the passed in watchee reference for easy chaining `e.g. return context.unwatch(ref)`
    @discardableResult
    func unwatch<Watchee>(
        _ watchee: Watchee,
        file: String,
        line: UInt
    ) -> Watchee where Watchee: DeathWatchable
}
