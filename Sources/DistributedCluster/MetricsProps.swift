// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import CoreMetrics
import Dispatch
import NIO

public struct MetricsProps: CustomStringConvertible {
    public static var disabled: Self {
        .init(group: "", active: [])
    }

    /// Set of built-in active metrics
    public var active: ActiveMetricsOptionSet

    public var enabled: Bool {
        !self.active.isEmpty
    }

    /// Will be prefixed with `systemName` and suffixed with specific metric names to form a specific metric's label.
    public var group: String

    public var description: String {
        "MetricsProps(active: \(self.active), group: \(self.group))"
    }

    public init(group: String, active: ActiveMetricsOptionSet) {
        self.group = group
        self.active = active
    }
}
