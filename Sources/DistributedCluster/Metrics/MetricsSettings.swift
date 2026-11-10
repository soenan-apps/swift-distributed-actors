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

import DistributedActorsConcurrencyHelpers
import Metrics

/// Configure metrics exposed by the actor system.
public struct MetricsSettings {

    /// Configure the segments separator for use when creating labels;
    /// Some systems like graphite like "." as the separator, yet others may not treat this as legal character.
    ///
    /// Typical alternative values are "/" or "_", though consult your metrics backend before changing this setting.
    public var segmentSeparator: String = "."

    /// Prefix all metrics with this segment.
    ///
    /// Defaults to the actor system's name.
    public var systemName: String? {
        get {
            self.configuredSystemName
        }
        set {
            guard let newValue, !newValue.isEmpty else {
                self.configuredSystemName = nil
                return
            }
            self.configuredSystemName = newValue
        }
    }

    internal var configuredSystemName: String?

    /// Segment prefixed before all metrics exported automatically by the actor system.
    ///
    /// Effectively metrics are labelled as, e.g. `"first.sact.actors.lifecycle"`,
    /// where `"first"` is `systemName` and `"sact"` is the `systemMetricsPrefix`.
    public var systemMetricsPrefix: String?

    /// Segment prefixed to all SWIM metrics.
    public var clusterSWIMMetricsPrefix: String? = "cluster.swim"

    /// Creates settings with an optional actor-system metric prefix.
    public static func `default`(rootName: String?) -> Self {
        var settings: Self = Self()
        settings.systemName = rootName
        return settings
    }

    internal func makeLabel(_ segments: String...) -> String {
        let joinedSegments: String = segments.joined(separator: self.segmentSeparator)

        // this is purposefully not using more fluent patterns, to avoid array allocations etc.
        switch (self.systemName, self.systemMetricsPrefix) {
        case let (.some(root), .some(prefix)):
            return "\(root)\(self.segmentSeparator)\(prefix)\(self.segmentSeparator)\(joinedSegments)"

        case let (.none, .some(prefix)):
            return "\(prefix)\(self.segmentSeparator)\(joinedSegments)"

        case let (.some(root), .none):
            return "\(root)\(self.segmentSeparator)\(joinedSegments)"

        case (.none, .none):
            return joinedSegments
        }
    }
}
