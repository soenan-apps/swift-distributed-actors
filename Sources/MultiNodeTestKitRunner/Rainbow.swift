// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import ArgumentParser
import DistributedCluster
import MultiNodeTestKit
import NIOCore
import NIOPosix
import OrderedCollections

import struct Foundation.Date
import class Foundation.FileHandle
import struct Foundation.URL

internal enum Rainbow: String {
    case `default` = "\u{001B}[0;0m"
    case black = "\u{001B}[0;30m"
    case blue = "\u{001B}[0;34m"
    case cyan = "\u{001B}[0;36m"
    case green = "\u{001B}[0;32m"
    case magenta = "\u{001B}[0;35m"
    case red = "\u{001B}[0;31m"
    case white = "\u{001B}[0;37m"
    case yellow = "\u{001B}[0;33m"

    internal func name() -> String {
        switch self {
        case .black:
            return "Black"

        case .red:
            return "Red"

        case .green:
            return "Green"

        case .yellow:
            return "Yellow"

        case .blue:
            return "Blue"

        case .magenta:
            return "Magenta"

        case .cyan:
            return "Cyan"

        case .white:
            return "White"

        case .default:
            return "Default"
        }
    }
}

extension String {
    internal var black: String {
        self.colored(as: .black)
    }

    internal var red: String {
        self.colored(as: .red)
    }

    internal var green: String {
        self.colored(as: .green)
    }

    internal var yellow: String {
        self.colored(as: .yellow)
    }

    internal var blue: String {
        self.colored(as: .blue)
    }

    internal var magenta: String {
        self.colored(as: .magenta)
    }

    internal var cyan: String {
        self.colored(as: .cyan)
    }

    internal var white: String {
        self.colored(as: .white)
    }

    internal var `default`: String {
        self.colored(as: .default)
    }

    internal func colored(as color: Rainbow) -> String {
        "\(color.rawValue)\(self)\(Rainbow.default.rawValue)"
    }
}
