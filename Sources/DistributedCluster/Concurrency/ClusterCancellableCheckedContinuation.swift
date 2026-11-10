// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsConcurrencyHelpers
import NIOConcurrencyHelpers

/// A checked continuation that offers easier APIs for working with cancellation,
/// as well as has its unique identity.
internal final class ClusterCancellableCheckedContinuation<Success>: Hashable, @unchecked Sendable
where Success: Sendable {
    private struct State: Sendable {
        var cancelled: Bool = false
        var onCancel: (@Sendable (ClusterCancellableCheckedContinuation<Success>) -> Void)?
        var continuation: CheckedContinuation<Success, any Error>?
    }

    private let stateBox: NIOLockedValueBox<State>

    internal var isCancelled: Bool {
        self.stateBox.withLockedValue { $0.cancelled }
    }

    internal init() {
        self.stateBox = .init(State())
    }

    internal static func == (
        lhs: ClusterCancellableCheckedContinuation,
        rhs: ClusterCancellableCheckedContinuation
    ) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    internal func setContinuation(_ continuation: CheckedContinuation<Success, any Error>) -> Bool {
        var alreadyCancelled: Bool = false
        self.stateBox.withLockedValue { state in
            if state.cancelled {
                alreadyCancelled = true
            } else {
                state.continuation = continuation
            }
        }
        if alreadyCancelled {
            continuation.resume(throwing: CancellationError())
        }
        return !alreadyCancelled
    }

    /// Register a cancellation handler, or call it immediately if the continuation was already cancelled.
    @Sendable
    internal func onCancel(handler: @Sendable @escaping (ClusterCancellableCheckedContinuation<Success>) -> Void) {
        let alreadyCancelled: Bool = self.stateBox.withLockedValue { state in
            if state.cancelled {
                return true
            }

            state.onCancel = handler
            return false
        }
        if alreadyCancelled {
            handler(self)
        }
    }

    private func withContinuation(
        cancelled: Bool = false,
        _ operation: (CheckedContinuation<Success, any Error>) -> Void
    ) {
        var safeContinuation: CheckedContinuation<Success, any Error>?
        var safeOnCancel: (@Sendable (ClusterCancellableCheckedContinuation<Success>) -> Void)?
        self.stateBox.withLockedValue { (state: inout State) in
            state.cancelled = state.cancelled || cancelled
            safeContinuation = state.continuation
            safeOnCancel = state.onCancel
            state.continuation = nil
            state.onCancel = nil
        }
        if let safeContinuation {
            operation(safeContinuation)
        }
        if cancelled {
            safeOnCancel?(self)
        }
    }

    internal func resume(returning value: Success) {
        self.withContinuation { continuation in
            continuation.resume(returning: value)
        }
    }

    internal func resume(throwing error: any Error) {
        self.withContinuation { continuation in
            continuation.resume(throwing: error)
        }
    }

    internal func cancel() {
        self.withContinuation(cancelled: true) { continuation in
            continuation.resume(throwing: CancellationError())
        }
    }

    internal func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    internal func resume() where Success == Void {
        self.resume(returning: ())
    }
}

internal func withClusterCancellableCheckedContinuation<Success>(
    _ body: @escaping (ClusterCancellableCheckedContinuation<Success>) -> Void,
    of _: Success.Type = Success.self,
    function: String = #function
) async throws -> Success where Success: Sendable {
    let cancellable: ClusterCancellableCheckedContinuation<Success> = ClusterCancellableCheckedContinuation<Success>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation(function: function) { continuation in
            if cancellable.setContinuation(continuation) {
                body(cancellable)
            }
        }
    } onCancel: {
        cancellable.cancel()
    }
}
