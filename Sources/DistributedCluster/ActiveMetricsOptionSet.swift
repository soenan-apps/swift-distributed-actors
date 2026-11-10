// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

/// Defines which per-actor group metrics are enabled.
public struct ActiveMetricsOptionSet: OptionSet {
    public static let mailbox: Self = Self(rawValue: 1 << 0)
    public static let messageProcessing: Self = Self(rawValue: 1 << 1)
    public static let serialization: Self = Self(rawValue: 1 << 2)
    public static let deserialization: Self = Self(rawValue: 1 << 3)
    public static let all: ActiveMetricsOptionSet = [
        .mailbox,
        .messageProcessing,
        .serialization,
        .deserialization,
    ]

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
