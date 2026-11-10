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

/// An actor-reference factory that owns and can stop child actors.
public protocol ChildActorRefFactory: ActorRefFactory {
    /// Child actors protected by the factory's synchronization boundary.
    var children: Children { get set }  // lock-protected

    /// Stops the selected child, rejecting references outside this factory.
    func stop<Message>(child ref: ActorRef<Message>) throws
    where Message: Codable
}
