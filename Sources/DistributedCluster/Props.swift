// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

/// Configures an actor's mailbox, dispatcher, metadata, metrics, and supervision.
/// Fluent operations return a copy; metadata storage is shared unless explicitly deep-copied.
public struct Props: @unchecked Sendable {
    @TaskLocal internal static var forSpawn: Props = .init()

    /// Properties for an actor with a well-known identity.
    public static let wellKnown: Self = Self().asWellKnown

    internal var dispatcher: DispatcherProps = .default
    internal var supervision: SupervisionProps = .default
    internal var metadata: ActorMetadata
    public var metrics: MetricsProps
    internal var wellKnown: Bool = false

    /// Sets the well-known metadata name used when spawning.
    internal var wellKnownName: String? {
        get {
            self.metadata.wellKnown
        }
        set {
            self.wellKnown = newValue != nil
            self.metadata.wellKnown = newValue
        }
    }

    /// Spawns under the system namespace.
    internal var systemActor: Bool = false

    /// Supplies the actor name during distributed identity assignment.
    internal var knownActorName: String? {
        get {
            self.metadata.knownActorName
        }
        set {
            self.metadata.knownActorName = newValue
        }
    }

    /// Makes resolution use this ID rather than assigning a new one.
    internal var designatedActorID: ActorID?

    @usableFromInline internal var distributedActor: Bool = false

    /// Returns a copy requesting a well-known actor incarnation.
    /// Use only when the identity is occupied by a single actor incarnation.
    public var asWellKnown: Self {
        var props: Self = self
        props.wellKnown = true
        return props
    }

    /// Returns a copy requesting a unique actor incarnation.
    public var asNotSoWellKnown: Self {
        var props: Self = self
        props.wellKnown = false
        return props
    }

    public init(metadata: ActorMetadata = ActorMetadata(), metrics: MetricsProps = .disabled) {
        self.metadata = metadata
        self.metrics = metrics
    }

    /// Creates properties with the supplied dispatcher and otherwise default values.
    internal static func dispatcher(_ dispatcher: DispatcherProps) -> Self {
        var props: Self = Self()
        props.dispatcher = dispatcher
        return props
    }

    /// Reports per-actor metrics in the supplied group rather than under individual actor identities.
    public static func metrics(
        group: String,
        measure activeMetrics: ActiveMetricsOptionSet,
        _ configure: (inout MetricsProps) -> Void = { _ in () }
    ) -> Self {
        Self().metrics(group: group, measure: activeMetrics) { configure(&$0) }
    }

    internal func consume() -> Self {
        let copy: Self = self.deepCopy()
        self.metadata.clear()
        return copy
    }

    /// Copies mutable metadata storage along with the actor's configuration.
    internal func deepCopy() -> Self {
        var props: Self = Self(metadata: ActorMetadata(), metrics: self.metrics)
        props.supervision = self.supervision
        props.dispatcher = self.dispatcher
        props.systemActor = self.systemActor
        props.designatedActorID = self.designatedActorID
        if props.knownActorName == nil {
            props.knownActorName = self.knownActorName
        }
        props.wellKnownName = self.wellKnownName
        props.wellKnown = self.wellKnown
        return props
    }

    /// Returns a copy with the supplied dispatcher.
    internal func dispatcher(_ dispatcher: DispatcherProps) -> Self {
        var props: Self = self
        props.dispatcher = dispatcher
        return props
    }

    /// Returns a copy reporting the selected metrics under the supplied group.
    public func metrics(
        group: String,
        measure activeMetrics: ActiveMetricsOptionSet,
        _ configure: (inout MetricsProps) -> Void = { _ in () }
    ) -> Self {
        var props: Self = self
        var metricsProps: MetricsProps = MetricsProps(group: group, active: activeMetrics)
        configure(&metricsProps)
        props.metrics = metricsProps
        return props
    }
}
