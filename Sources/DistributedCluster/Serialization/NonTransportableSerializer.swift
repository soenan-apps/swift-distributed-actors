// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import CDistributedActorsMailbox
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf

internal class NonTransportableSerializer<Message>: Serializer<Message> {
    override internal func serialize(_: Message) throws -> Serialization.Buffer {
        throw SerializationError(.unableToSerialize(hint: "\(Self.self): \(Message.self)"))
    }

    override internal func deserialize(from _: Serialization.Buffer) throws -> Message {
        throw SerializationError(.unableToDeserialize(hint: "\(Self.self): \(Message.self)"))
    }
}
