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

/// INTERNAL API: May change without any prior notice.
///
internal protocol AbstractAdapter: ActorTreeTraversable {
    var fromType: Any.Type { get }

    var id: ActorID { get }
    var deadLetters: ActorRef<DeadLetter> { get }
    var system: ClusterSystem? { get }

    /// Try to `tell` given message, if the type matches the adapted (or direct) message type, it will be delivered.
    func trySendUserMessage(_ message: Any, file: String, line: UInt)
    func sendSystemMessage(_ message: SystemMessages, file: String, line: UInt)

    /// Synchronously stops the adapter ref and send terminated messages to all watchers.
    func stop()

}
