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

import Distributed
import DistributedActorsConcurrencyHelpers
import Foundation
import Logging

extension Logger.MetadataValue {
    /// Retains the value for its custom pretty description.
    public static func pretty<T>(_ value: T) -> Logger.Metadata.Value where T: CustomPrettyStringConvertible {
        Self.stringConvertible(PrettyMetadataValue(value))
    }

    /// Uses a custom pretty value when available, otherwise its string representation.
    public static func pretty<T>(_ value: T) -> Logger.Metadata.Value {
        if let pretty = value as? CustomPrettyStringConvertible {
            return Self.stringConvertible(PrettyMetadataValue(pretty))
        }
        return .string("\(value)")
    }
}
