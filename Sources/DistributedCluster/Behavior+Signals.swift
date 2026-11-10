// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Behavior {
    /// Allows reacting to `Signal`s, such as lifecycle events.
    ///
    /// This behavior _adds_ signal handling to the existing message behavior
    /// (e.g. `receive`) rather than replacing it.
    ///
    /// #### Example usage
    /// ```
    /// let withSignalHandling = behavior.receiveSignal { context, signal in
    ///     guard let terminated = signal as? Signals.Terminated else {
    ///         return .unhandled
    ///     }
    ///     if terminated.id.name == "Juliet" {
    ///         return .stop // if Juliet died, we end ourselves as well
    ///     } else {
    ///         return .ignore
    ///     }
    /// }
    /// ```
    ///
    /// - SeeAlso: `Signals` for a listing of signals that may be handled using this behavior.
    /// - SeeAlso: `receiveSpecificSignal` for convenience version of this behavior, simplifying handling a single type
    /// of `Signal`.
    public static func receiveSignal(
        _ handle: @escaping (ActorContext<Message>, Signal) throws -> Behavior<Message>
    ) -> Behavior<Message> {
        Behavior(
            underlying: .signalHandling(
                handleMessage: .unhandled,
                handleSignal: handle
            )
        )
    }

    /// Convenience function similar to `Behavior.receiveSignal` however allowing for easier handling of a specific
    /// signal type, e.g.:
    ///
    /// #### Example usage
    /// ```
    /// return .receiveSpecificSignal(Signals.Terminated.self) { context, terminated in
    ///     if terminated.id.name == "Juliet" {
    ///         return .stop // if Juliet died, we end ourselves as well
    ///     } else {
    ///         return .ignore
    ///     }
    /// }
    /// ```
    ///
    /// - SeeAlso: `Signals` for a listing of signals that may be handled using this behavior.
    /// - SeeAlso: `receiveSignal` which allows receiving multiple types of signals.
    public static func receiveSpecificSignal<SpecificSignal: Signal>(
        _: SpecificSignal.Type,
        _ handle: @escaping (ActorContext<Message>, SpecificSignal) throws -> Behavior<Message>
    ) -> Behavior<Message> {
        Self.signalHandling(handleMessage: .unhandled) { context, signal in
            switch signal {
            case let matchingSignal as SpecificSignal:
                return try handle(context, matchingSignal)

            default:
                return .unhandled
            }
        }
    }

    /// Allows reacting to `Signal`s, such as lifecycle events.
    ///
    /// This behavior _adds_ signal handling to the existing message behavior
    /// (e.g. `receive`) rather than replacing it.
    ///
    /// #### Example usage
    /// ```
    /// let withSignalHandling = behavior.receiveSignal { context, signal in
    ///     guard let terminated = signal as? Signals.Terminated else {
    ///         return .unhandled
    ///     }
    ///     if terminated.id.name == "Juliet" {
    ///         return .stop // if Juliet died, we end ourselves as well
    ///     } else {
    ///         return .same
    ///     }
    /// }
    /// ```
    ///
    /// - SeeAlso: `Signals` for a listing of signals that may be handled using this behavior.
    /// - SeeAlso: `receiveSpecificSignal` for convenience version of this behavior, simplifying handling a single type
    /// of `Signal`.
    public func receiveSignal(
        _ handle: @escaping (ActorContext<Message>, Signal) throws -> Behavior<Message>
    ) -> Behavior<Message> {
        Behavior(
            underlying: .signalHandling(
                handleMessage: self,
                handleSignal: handle
            )
        )
    }

    /// 既存のメッセージ処理を保ったまま、非同期のシグナル処理を追加する。
    public func receiveSignalAsync(
        _ handle: @escaping @Sendable (ActorContext<Message>, Signal) async throws -> Behavior<Message>
    ) -> Behavior<Message> {
        Behavior(
            underlying: .signalHandlingAsync(
                handleMessage: self,
                handleSignal: handle
            )
        )
    }

    /// Convenience function similar to `Behavior.receiveSignal` however allowing for easier handling of a specific
    /// signal type, e.g.:
    ///
    /// #### Example usage
    /// ```
    /// let withSignalHandling = behavior.receiveSpecificSignal(Signals.Terminated.self) { context, terminated in
    ///     if terminated.id.name == "Juliet" {
    ///         return .stop // if Juliet died, we end ourselves as well
    ///     } else {
    ///         return .ignore
    ///     }
    /// }
    /// ```
    ///
    /// - SeeAlso: `Signals` for a listing of signals that may be handled using this behavior.
    /// - SeeAlso: `receiveSignal` which allows receiving multiple types of signals.
    public func receiveSpecificSignal<SpecificSignal: Signal>(
        _: SpecificSignal.Type,
        _ handle: @escaping (ActorContext<Message>, SpecificSignal) throws -> Behavior<Message>
    ) -> Behavior<Message> {
        // better type printout so we know we only handle SpecificSignal with this one
        self.receiveSignal { context, signal in
            switch signal {
            case let matchingSignal as SpecificSignal:
                return try handle(context, matchingSignal)

            default:
                return .unhandled
            }
        }
    }

}
