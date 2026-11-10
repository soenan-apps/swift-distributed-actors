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

extension MetaType: AnyMetaType {
    @usableFromInline internal var asHashable: AnyHashable {
        AnyHashable(self)
    }

    @usableFromInline internal var underlying: Any.Type? {
        self.underlyingType
    }

    @usableFromInline
    internal func `is`(_ other: AnyMetaType) -> Bool {
        self.asHashable == other.asHashable
    }

    @usableFromInline
    internal func isInstance(_ obj: Any) -> Bool {
        obj is T
    }

}
