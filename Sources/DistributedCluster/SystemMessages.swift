// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

/// Messages reserved for actor runtime internals; user code must use signals instead.
///
/// System messages are never silently dropped. They are drained to dead letters on termination.
/// Network delivery buffers, acknowledges, and redelivers them in send order. If delivery can no
/// longer be guaranteed, the association is terminated and the remote node is marked down.
@usableFromInline
internal enum SystemMessages: Equatable {
    /// Delivers a custom signal unchanged to the recipient actor.
    case carrySignal(Signal)
    /// Reports child termination, including a failure escalated to the parent.
    case childTerminated(ref: AddressableActorRef, TerminationCircumstances)
    /// Treats every watched actor on the terminated node as terminated.
    case nodeTerminated(Cluster.Node)
    /// Completes the asynchronous operation awaited by a suspended actor.
    case resume(Result<Any, Error>)
    /// Evaluates the initial behavior; never sent over the wire.
    case start
    /// Requests that the child actor stop.
    case stop
    /// Reports termination after a watch, distinguishing confirmed from assumed termination.
    case terminated(ref: AddressableActorRef, existenceConfirmed: Bool, idTerminated: Bool)
    /// The last message processed after the mailbox has stopped accepting messages.
    /// Processing it must close the mailbox and release its resources.
    case tombstone
    /// Removes a watch relationship.
    case unwatch(watchee: AddressableActorRef, watcher: AddressableActorRef)
    /// Installs a watch relationship.
    case watch(watchee: AddressableActorRef, watcher: AddressableActorRef)

    internal static let metaType: MetaType<SystemMessages> = MetaType(Self.self)

    @inlinable
    internal static func terminated(ref: AddressableActorRef) -> Self {
        .terminated(ref: ref, existenceConfirmed: false, idTerminated: false)
    }

    @inlinable
    internal static func terminated(ref: AddressableActorRef, existenceConfirmed: Bool) -> Self {
        .terminated(ref: ref, existenceConfirmed: existenceConfirmed, idTerminated: false)
    }

    @inlinable
    internal static func terminated(ref: AddressableActorRef, idTerminated: Bool) -> Self {
        .terminated(ref: ref, existenceConfirmed: false, idTerminated: idTerminated)
    }

    @usableFromInline
    internal static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.start, .start):
            return true

        case let (.watch(leftWatchee, leftWatcher), .watch(rightWatchee, rightWatcher)):
            return leftWatchee.id == rightWatchee.id && leftWatcher.id == rightWatcher.id

        case let (.unwatch(leftWatchee, leftWatcher), .unwatch(rightWatchee, rightWatcher)):
            return leftWatchee.id == rightWatchee.id && leftWatcher.id == rightWatcher.id

        case let (
            .terminated(leftRef, leftExisted, leftNodeTerminated),
            .terminated(rightRef, rightExisted, rightNodeTerminated)
        ):
            return leftRef.id == rightRef.id && leftExisted == rightExisted && leftNodeTerminated == rightNodeTerminated

        case let (.childTerminated(leftRef, _), .childTerminated(rightRef, _)):
            return leftRef.id == rightRef.id

        case let (.nodeTerminated(leftAddress), .nodeTerminated(rightAddress)):
            return leftAddress == rightAddress

        case (.tombstone, .tombstone):
            return true

        case (.stop, .stop):
            return true

        case (.start, _),
            (.watch, _),
            (.unwatch, _),
            (.carrySignal, _),
            (.tombstone, _),
            (.terminated, _),
            (.childTerminated, _),
            (.stop, _),
            (.resume, _),
            (.nodeTerminated, _):
            return false
        }
    }
}
