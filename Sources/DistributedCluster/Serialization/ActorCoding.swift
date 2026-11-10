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

import Foundation  // for Codable
import NIO
import NIOFoundationCompat

internal enum ActorCoding {
    internal enum CodingKeys: CodingKey {
        case incarnation
        case metadata
        case node
        case path
        case type
    }

    internal enum MetadataKeys: CodingKey {
        case custom(String)
        case path
        case type
        case wellKnown

        internal var intValue: Int? {
            switch self {
            case .path:
                return 0

            case .type:
                return 1

            case .wellKnown:
                return 2

            case .custom:
                return 64
            }
        }

        internal var stringValue: String {
            switch self {
            case .path:
                return "$path"

            case .type:
                return "$type"

            case .wellKnown:
                return "$wellKnown"

            case .custom(let id):
                return id
            }
        }

        internal init?(stringValue: String) {
            switch stringValue {
            case "$path":
                self = .path

            case "$type":
                self = .type

            case "$wellKnown":
                self = .wellKnown

            default:
                self = .custom(stringValue)
            }
        }

        internal init?(intValue _: Int) {
            nil
        }
    }
}
