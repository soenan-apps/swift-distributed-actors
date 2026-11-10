// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO
import NIOSSL
import ServiceDiscovery
import SWIM

import class Foundation.ProcessInfo

/// Configure initial contact point discovery to use a `ServiceDiscovery` implementation.
///
/// By providing a service discovery implementation, the `ClusterSystem` will reach out to nodes discovered using this
/// mechanism,
/// in an attempt to form (or join) a cluster with those nodes. These typically should include a few initial contact
/// points, but can also include
/// all the nodes of an existing cluster.
public struct ServiceDiscoverySettings {
    internal typealias Subscription = (
        @escaping (Result<[Cluster.Endpoint], Error>) -> Void,
        @escaping (CompletionReason) -> Void
    ) -> CancellationToken?

    internal enum ServiceDiscoveryImplementation {
        case clusterDaemon(endpoint: Cluster.Endpoint, initialize: (ClusterSystem) -> Void)
        case dynamic(serviceDiscovery: AnyServiceDiscovery, subscribe: Subscription)
        case `static`(endpoints: Set<Cluster.Endpoint>, subscribe: Subscription)
    }

    /// Locate the default `ClusterD` process and use it for discovering cluster nodes.
    public static var clusterd: Self {
        Self.clusterd(endpoint: nil)
    }

    internal let implementation: ServiceDiscoveryImplementation

    /// 検出されたendpointをクラスタのcontact pointとして使う。
    public init<Discovery: ServiceDiscovery>(_ implementation: Discovery, service: Discovery.Service)
    where Discovery.Instance == Cluster.Endpoint {
        self.implementation = .dynamic(serviceDiscovery: AnyServiceDiscovery(implementation)) { onNext, onComplete in
            implementation.subscribe(to: service, onNext: onNext, onComplete: onComplete)
        }
    }

    /// 検出されたinstanceをendpointへ変換してcontact pointとして使う。
    public init<Discovery: ServiceDiscovery>(
        _ implementation: Discovery,
        service: Discovery.Service,
        mapInstanceToNode transformer: @escaping (Discovery.Instance) throws -> Cluster.Endpoint
    ) {
        let mappedDiscovery: MapInstanceServiceDiscovery<Discovery, Cluster.Endpoint> = implementation.mapInstance(
            transformer
        )
        self.implementation = .dynamic(serviceDiscovery: AnyServiceDiscovery(mappedDiscovery)) { onNext, onComplete in
            mappedDiscovery.subscribe(to: service, onNext: onNext, onComplete: onComplete)
        }
    }

    /// 固定のendpoint集合を一度だけ通知する。
    public init(static nodes: Set<Cluster.Endpoint>) {
        self.implementation = .static(endpoints: nodes) { onNext, _ in
            // Static discovery never completes and has no cancellation token.
            onNext(.success(Array(nodes)))
            return nil
        }
    }

    internal init(clusterdEndpoint: Cluster.Endpoint) {
        self.implementation = .clusterDaemon(endpoint: clusterdEndpoint) { system in
            system.log.info("Joining [clusterd] at \(clusterdEndpoint)")
            system.cluster.join(endpoint: clusterdEndpoint)
        }
    }

    /// 指定されたdaemonへ接続してクラスタnodeを検出する。
    public static func clusterd(endpoint: Cluster.Endpoint?) -> Self {
        Self(clusterdEndpoint: endpoint ?? ClusterDaemon.defaultEndpoint)
    }

    /// 固定のendpoint集合をcontact pointとして使う。
    public static func seed(nodes: Set<Cluster.Endpoint>) -> Self {
        .init(static: nodes)
    }

    /// Similar to `ServiceDiscovery.subscribe` however it allows the handling of the listings to be generic and handled
    /// by the cluster system.
    /// This function is only intended for internal use by the `DiscoveryShell`.
    internal func subscribe(
        onNext nextResultHandler: @escaping (Result<[Cluster.Endpoint], Error>) -> Void,
        onComplete completionHandler: @escaping (CompletionReason) -> Void
    ) -> CancellationToken? {
        switch self.implementation {
        case let .static(_, subscribe),
            let .dynamic(_, subscribe):
            subscribe(nextResultHandler, completionHandler)

        case .clusterDaemon:
            .none
        }
    }

    internal func initializeClusterd(_ system: ClusterSystem) {
        switch self.implementation {
        case let .clusterDaemon(_, initialize):
            initialize(system)

        default:
            break
        }
    }
}
