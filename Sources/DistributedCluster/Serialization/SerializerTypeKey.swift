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
import Distributed
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf
import SWIM

@usableFromInline
internal struct SerializerTypeKey: Hashable, CustomStringConvertible {
    @usableFromInline internal let type: Any.Type
    @usableFromInline internal var typeID: ObjectIdentifier {
        .init(self.type)
    }

    @usableFromInline internal let ensure: (Serialization) throws -> Void

    @usableFromInline internal var description: String {
        "SerializerTypeKey(\(String(reflecting: self.type)), typeID: \(self.typeID))"
    }

    @usableFromInline
    internal init(any: Any.Type) {
        self.type = any
        self.ensure = { _ in () }
    }

    @usableFromInline
    internal init<Message: Codable>(_ type: Message.Type) {
        self.type = type
        self.ensure = { serialization in
            try serialization.ensureSerializer(type)
        }
    }

    @usableFromInline
    internal static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.typeID == rhs.typeID
    }

    @usableFromInline
    internal func ensureSerializer(_ serialization: Serialization) throws {
        try self.ensure(serialization)
    }

    @usableFromInline
    internal func hash(into hasher: inout Hasher) {
        self.typeID.hash(into: &hasher)
    }

}
