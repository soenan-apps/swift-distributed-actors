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

import Foundation
import XCTest

extension Collection where Element: Equatable {
    internal func commonPrefix<OtherSequence>(with other: OtherSequence) -> SubSequence
    where OtherSequence: Collection, Element == OtherSequence.Element {
        var otherIterator: OtherSequence.Iterator = other.makeIterator()
        return self.prefix { element in element == otherIterator.next() }
    }
}
