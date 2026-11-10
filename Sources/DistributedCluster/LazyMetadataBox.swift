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

/// Delays rendering of metadata value (e.g. into a string)
///
/// NOT thread-safe, so all access should be guarded some synchronization method, e.g. only access from an Actor.
internal class LazyMetadataBox: CustomStringConvertible {
    private var lazyValue: (() -> CustomStringConvertible)?
    private var cachedValue: String?

    /// This allows caching a value in case it is accessed via an by name subscript,
    /// rather than as part of rendering all metadata that a LoggingContext was carrying
    internal var value: String {
        if let renderValue = self.lazyValue {
            self.cachedValue = renderValue().description
            self.lazyValue = nil
        }

        guard let cachedDescription: String = self.cachedValue else {
            preconditionFailure("cachedValue MUST NOT be nil once lazyValue() has run.")
        }
        return cachedDescription.description
    }

    internal var description: String {
        "\(self.value)"
    }

    internal init(_ lazyValue: @escaping () -> CustomStringConvertible) {
        self.lazyValue = lazyValue
    }
}
