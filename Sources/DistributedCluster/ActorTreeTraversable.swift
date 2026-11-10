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

/// INTERNAL API
internal protocol ActorTreeTraversable {
    func traverse<T>(
        context: TraversalContext<T>,
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T>

    /// Resolves the given actor path against the underlying actor tree.
    ///
    /// Depending on the underlying implementation, the returned ref MAY be a remote one.
    ///
    /// - Returns: `deadLetters` if actor path resolves to no live actor, a valid `ActorRef` otherwise.
    func resolve<Message>(context: ResolveContext<Message>) -> ActorRef<Message> where Message: Codable

    /// Resolves the given actor path against the underlying actor tree.
    ///
    /// Depending on the underlying implementation, the returned ref MAY be a remote one.
    ///
    /// - Returns: `deadLetters` if actor path resolves to no live actor, a valid `ActorRef` otherwise.
    func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef
}
