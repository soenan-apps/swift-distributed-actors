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

import CDistributedActorsMailbox
import Dispatch
import Logging
import Metrics

import struct NIO.ByteBuffer

// Abstract override points must remain callable through the base type.
// swiftlint:disable unavailable_function
/// INTERNAL API: May change without prior notice.
/// EXTENSION POINT: Can be used to offer `ActorRef`s to other "special" entities, such as other
/// `_InternalActorTransport`s etc.
///
/// Similar to an `ActorCell` but for some delegated actual "entity".
/// This can be used to implement actor-like beings, which are backed by non-actor entities.

open class CellDelegate<Message: Codable> {
    /// The actor system owning the delegated entity; provided by subclasses.
    open var system: ClusterSystem {
        fatalError("Not implemented: \(#function)")
    }

    /// The stable identity of the delegated entity; provided by subclasses.
    open var id: ActorID {
        fatalError("Not implemented: \(#function)")
    }

    public init() {
        // nothing
    }

    /// Delivers a user message through the delegate's implementation.
    open func sendMessage(_: Message, file: String = #filePath, line: UInt = #line) {
        fatalError("Not implemented: \(#function), called from \(file):\(line)")
    }

    internal func sendSystemMessage(_: SystemMessages, file: String = #filePath, line: UInt = #line) {
        fatalError("Not implemented: \(#function), called from \(file):\(line)")
    }

    /// Schedules a closure through the delegate's message-processing context.
    open func sendClosure(_: () throws -> Void, file: String = #filePath, line: UInt = #line) {
        fatalError("Not implemented: \(#function), called from \(file):\(line)")
    }

    /// Delivers a message to the identified sub-receive handler.
    open func sendSubMessage<SubMessage>(
        _: SubMessage,
        identifier _: AnySubReceiveId,
        subReceiveAddress _: ActorID,
        file: String = #filePath,
        line: UInt = #line
    ) {
        fatalError("Not implemented: \(#function), called from \(file):\(line)")
    }

    /// Delivers a message accepted by a registered message adapter.
    open func sendAdaptedMessage(_: Any, file: String = #filePath, line: UInt = #line) {
        fatalError("Not implemented: \(#function), called from \(file):\(line)")
    }
}
// swiftlint:enable unavailable_function
