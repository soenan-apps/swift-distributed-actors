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

/// Not intended to be used by end users.
///
/// Wraps the `DeadLettersActorRef` to get properly typed deadLetters refs.
internal final class DeadLetterAdapterPersonality: AbstractAdapter {
    internal let fromType: Any.Type = Never.self

    internal let deadLetters: ActorRef<DeadLetter>
    internal let deadRecipient: ActorID
    internal var id: ActorID {
        self.deadLetters.id
    }

    internal var system: ClusterSystem? {
        self.deadLetters.actorSystem
    }

    internal init(_ ref: ActorRef<DeadLetter>, deadRecipient: ActorID) {
        self.deadLetters = ref
        self.deadRecipient = deadRecipient
    }
    internal func trySendUserMessage(_ message: Any, file: String = #filePath, line: UInt = #line) {
        self.deadLetters.tell(
            DeadLetter(message, recipient: self.deadRecipient, sentAtFile: file, sentAtLine: line),
            file: file,
            line: line
        )
    }

    internal func sendSystemMessage(_ message: SystemMessages, file: String = #filePath, line: UInt = #line) {
        self.deadLetters.sendSystemMessage(message, file: file, line: line)
    }

    internal func stop() {
        // nothing to stop, a dead letters adapter is special
    }

    internal func traverse<T>(
        context _: TraversalContext<T>,
        _: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        .completed
    }

    internal func resolve<Message2>(context _: ResolveContext<Message2>) -> ActorRef<Message2> {
        self.deadLetters.adapted()
    }

    internal func resolveUntyped(context _: ResolveContext<Never>) -> AddressableActorRef {
        self.deadLetters.asAddressable
    }
}
