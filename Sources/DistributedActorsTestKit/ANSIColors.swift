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

internal enum ANSIColors: String {
    case black = "\u{001B}[0;30m"
    case blue = "\u{001B}[0;34m"
    case bold = "\u{001B}[1m"
    case cyan = "\u{001B}[0;36m"
    case green = "\u{001B}[0;32m"
    case magenta = "\u{001B}[0;35m"
    case red = "\u{001B}[0;31m"
    case reset = "\u{001B}[0;0m"
    case white = "\u{001B}[0;37m"
    case yellow = "\u{001B}[0;33m"
}
