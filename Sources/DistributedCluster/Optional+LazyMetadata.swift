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

extension Optional where Wrapped == Logger.MetadataValue {
    /// Defers rendering the supplied value until metadata is formatted.
    public static func lazyStringConvertible(
        _ makeValue: @escaping () -> CustomStringConvertible
    ) -> Logger.Metadata.Value {
        .stringConvertible(LazyMetadataBox { makeValue() })
    }

    /// Defers rendering the supplied string until metadata is formatted.
    public static func lazyString(_ makeValue: @escaping () -> String) -> Logger.Metadata.Value {
        self.lazyStringConvertible(makeValue)
    }
}
