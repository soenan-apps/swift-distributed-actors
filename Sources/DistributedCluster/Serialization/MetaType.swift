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

/// A meta type is a type eraser for any `T`, such that we can still perform `value is T` checks.
@usableFromInline
internal struct MetaType<T>: Hashable, CustomStringConvertible {
    internal let underlyingType: Any.Type?
    internal let id: ObjectIdentifier

    @usableFromInline internal var description: String {
        "MetaType<\(String(reflecting: T.self))"
    }

    internal init(_ base: T.Type) {
        self.underlyingType = base
        self.id = ObjectIdentifier(base)
    }

    internal init(from value: T) {
        let runtimeType: Any.Type = type(of: value as Any)
        self.underlyingType = runtimeType
        self.id = ObjectIdentifier(runtimeType)
    }

    @usableFromInline
    internal static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    @usableFromInline
    internal func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }

}
