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

import CoreMetrics
import DistributedActorsConcurrencyHelpers
import Metrics
import SWIM

/// Storage type for all metric instances an actor may be reporting.
/// These may be accessed by various threads, including from outside of the actor (!).
@usableFromInline
internal struct ActiveActorMetrics {
    @usableFromInline
    internal enum StoredMetric {
        case counter(Counter)
        case gauge(CoreMetrics.Gauge)
        case timer(CoreMetrics.Timer)
    }

    internal static var noop: Self {
        .init()
    }

    // Cheaper to check if a metric is enabled than the dictionary?
    @usableFromInline internal let active: ActiveMetricsOptionSet

    @usableFromInline internal let metrics: [ActiveMetricID: StoredMetric]

    private init() {
        self.active = []
        self.metrics = [:]
    }

    internal init(system: ClusterSystem, id _: ActorID, props: MetricsProps) {
        // initialize metric objects required by this instance
        let activeOptions: ActiveMetricsOptionSet = props.active
        self.active = activeOptions
        guard !activeOptions.isEmpty else {
            self.metrics = [:]
            return
        }

        let systemName: String? = system.name.isEmpty ? nil : system.name
        func label(_ name: String) -> String {
            [systemName, props.group, name].compactMap { $0 }.joined(separator: ".")
        }

        var metricValues: [ActiveMetricID: StoredMetric] = [:]
        if activeOptions.contains(.serialization) {
            metricValues[.serializationSize] = .gauge(Gauge(label: label("serialization.size")))
            metricValues[.serializationTime] = .timer(CoreMetrics.Timer(label: label("serialization.time")))
        }
        if activeOptions.contains(.deserialization) {
            metricValues[.deserializationSize] = .gauge(Gauge(label: label("deserialization.size")))
            metricValues[.deserializationTime] = .timer(CoreMetrics.Timer(label: label("deserialization.time")))
        }
        if activeOptions.contains(.mailbox) {
            metricValues[.mailboxCount] = .gauge(Gauge(label: label("mailbox.count")))
        }
        if activeOptions.contains(.messageProcessing) {
            // create message processing metricValues
        }

        self.metrics = metricValues
    }

    internal subscript(counter identifier: ActiveMetricID) -> Counter? {
        self.metrics[identifier].map { metric in
            guard case .counter(let counter) = metric else {
                preconditionFailure("Metric is not a counter")
            }
            return counter
        }
    }

    internal subscript(gauge identifier: ActiveMetricID) -> CoreMetrics.Gauge? {
        self.metrics[identifier].map { metric in
            guard case .gauge(let gauge) = metric else {
                preconditionFailure("Metric is not a gauge")
            }
            return gauge
        }
    }

    internal subscript(timer identifier: ActiveMetricID) -> CoreMetrics.Timer? {
        self.metrics[identifier].map { metric in
            guard case .timer(let timer) = metric else {
                preconditionFailure("Metric is not a timer")
            }
            return timer
        }
    }
}
