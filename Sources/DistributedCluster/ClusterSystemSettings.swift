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

import Logging
import NIO
import NIOSSL
import ServiceDiscovery
import SWIM

import class Foundation.ProcessInfo

/// Settings used to configure a `ClusterSystem`.
public struct ClusterSystemSettings {

    /// クラスタtransportのprotocol名。
    public typealias ProtocolName = String

    /// システム名と接続先の既定値。
    public enum Default {
        /// 既定のシステム名。
        public static let name: String = "ClusterSystem"
        /// 既定の待受host。
        public static let bindHost: String = "127.0.0.1"
        /// 既定の待受port。
        public static let bindPort: Int = 7_337
    }

    /// Default settings bound to the standard local cluster endpoint.
    public static var `default`: Self {
        let defaultEndpoint: Cluster.Endpoint = Cluster.Endpoint(
            systemName: Default.name,
            host: Default.bindHost,
            port: Default.bindPort
        )
        return Self(endpoint: defaultEndpoint)
    }

    /// Behaviorを実行するactorの設定。
    public var actor: ActorSettings = .default

    internal var actorMetadata: ActorIDMetadataSettings = .default

    /// Configuration of cluster system plugins.
    ///
    /// Mostly used to enable additional plugins during initial system configuration.
    public var plugins: PluginsSettings = .default

    /// Actorの登録と検索に関する設定。
    public var receptionist: ReceptionistSettings = .default

    /// メッセージのシリアライズとデシリアライズに関する設定。
    public var serialization: Serialization.Settings = .default

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Connection establishment, protocol settings

    // Internal for tests only
    /// If `true` the `ClusterSystem` starts the cluster subsystem upon startup.
    /// The address bound to will be `bindAddress`.
    public internal(set) var enabled: Bool = true

    /// If configured, the system will receive contact point updates.
    public var discovery: ServiceDiscoverySettings?

    /// Hostname used to accept incoming connections from other nodes.
    public var bindHost: String {
        get {
            self.endpoint.host
        }
        set {
            self.endpoint.host = newValue
        }
    }

    /// Port used to accept incoming connections from other nodes.
    public var bindPort: Int {
        get {
            self.endpoint.port
        }
        set {
            self.endpoint.port = newValue
        }
    }

    /// Node representing this node in the cluster.
    /// Note that most of the time `uniqueBindNode` is more appropriate, as it includes this node's unique id.
    public var endpoint: Cluster.Endpoint {
        didSet {
            self.serialization.localNode = self.bindNode
            self.metrics.systemName = self.endpoint.systemName
            self.swim.metrics.systemName = self.endpoint.systemName
        }
    }

    /// `Cluster.Node.Identifier` to be used when exposing `Cluster.Node` for node configured by using these settings.
    public var nid: Cluster.Node.Identifier {
        didSet {
            self.serialization.localNode = self.bindNode
        }
    }

    /// Reflects the `bindAddress` however carries a uniquely assigned UID.
    /// The UID remains the same throughout updates of the `bindAddress` field.
    public var bindNode: Cluster.Node {
        .init(endpoint: self.endpoint, nid: self.nid)
    }

    /// Time after which a the binding of the server port should fail.
    public var bindTimeout: Duration = .seconds(3)

    /// Timeout for unbinding the server port of this node (used when shutting down).
    public var unbindTimeout: Duration = .seconds(3)

    /// Time after which a connection attempt will fail if no connection could be established.
    public var connectTimeout: Duration = .milliseconds(500)

    /// Backoff to be applied when attempting a new connection and handshake with a remote system.
    public var handshakeReconnectBackoff: BackoffStrategy = Backoff.exponential(
        initialInterval: .milliseconds(300),
        multiplier: 1.5,
        capInterval: .seconds(3),
        maxAttempts: 32
    )

    /// Defines the Time-To-Live of an association, i.e. when it shall be completely dropped from the tombstones list.
    ///
    /// An association ("unique connection identifier between two nodes") is kept as tombstone when severing a
    /// connection between nodes,
    /// in order to avoid accidental re-connections to given node. Once a node has been downed, removed, and
    /// disassociated, it MUST NOT be
    /// communicated with again. Tombstones are used to ensure this, even if the downed ("zombie") node, attempts to
    /// reconnect.
    public var associationTombstoneTTL: Duration = .hours(24) * 1

    /// Defines the interval with which the list of associated tombstones is freed from expired tombstones.
    public var associationTombstoneCleanupInterval: Duration = .minutes(10)

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Cluster protocol versioning

    /// `ProtocolVersion` to be used when exposing `Cluster.Node` for node configured by using these settings.
    public internal(set) var protocolVersion: ClusterSystem.Version = ClusterSystem.protocolVersion

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Cluster.Membership Gossip

    /// クラスタメンバー間でmembership gossipを送る間隔。
    public var membershipGossipInterval: Duration = .seconds(1)

    // since we talk to many peers one by one; even as we proceed to the next round after `membershipGossipInterval`
    // A reply may arrive while gossiping with the next peer, so the acknowledgement timeout need not be rushed.
    //
    // A missing ACK is not terminal, may happen, and we'll then gossip with that peer again (e.g. if it had some form
    // of network trouble for a moment).
    /// Membership gossipへの応答を待つ時間。
    public var membershipGossipAcknowledgementTimeout: Duration = .seconds(1)

    /// Membership gossip間隔のランダム化に用いる係数。
    public var membershipGossipIntervalRandomFactor: Double = 0.2

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Leader Election

    /// クラスタのleaderを自動選出する方法。
    public var autoLeaderElection: LeadershipSelectionSettings = .lowestReachable(minNumberOfMembers: 2)

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Distributed Actor Calls

    /// A "remote call" is any function call of a `distributed` function on a 'remote' distributed actor.
    public var remoteCall: RemoteCallSettings = .default

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: TLS & Security settings

    /// If set, all communication with other nodes will be secured using TLS.
    ///
    /// The configuration is a `NIOSSL.TLSConfiguration`, so please refer to
    /// [swift-nio-ssl](https://github.com/apple/swift-nio-ssl) documentation for more details about it.
    ///
    /// - SeeAlso: `NIOSSL.NIOSSLContext`
    public var tls: TLSConfiguration?

    /// Callback invoked when a passphrase is required for TLS.
    ///
    /// - SeeAlso: `NIOSSL.NIOSSLContext`
    public var tlsPassphraseCallback: NIOSSLPassphraseCallback<[UInt8]>?

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: NIO

    // do we need to separate server and client sides? Sounds like a reasonable thing to do.
    /// If set, this event loop group will be used by the cluster infrastructure.
    public var eventLoopGroup: EventLoopGroup?

    /// Allocator to be used for allocating byte buffers for coding/decoding messages.
    public var allocator: ByteBufferAllocator = NIO.ByteBufferAllocator()

    // ====
    // ----------------------------------------------------------------------------------------------------------------
    // MARK: Cluster membership and failure detection

    /// Strategy how members determine if others (or myself) shall be marked as `.down`.
    /// This strategy should be set to the same (or compatible) strategy on all members of a cluster to avoid split
    /// brain situations.
    public var downingStrategy: DowningStrategySettings = .timeout(.default)

    /// When this member node notices it has been marked as `.down` in the membership, it can automatically perform an
    /// action.
    /// This setting determines which action to take. Generally speaking, the best course of action is to quickly and
    /// gracefully
    /// shut down the node and process, potentially leaving a higher level orchestrator to replace the node (e.g. k8s
    /// starting a new pod for the cluster).
    public var onDownAction: OnDownActionStrategySettings = .gracefulShutdown(delay: .seconds(3))

    /// Configures the SWIM cluster membership implementation (which serves as our failure detector).
    public var swim: SWIM.Settings

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Logging

    /// If enabled, logs membership changes (including the entire membership table from the perspective of the current
    /// node).
    public var logMembershipChanges: Logger.Level? = .debug

    /// Traces all incoming and outgoing cluster protocol communication, including handshakes and remote messages.
    /// Messages are prefixed with `[tracelog:cluster]`.
    #if SACT_TRACE_CLUSTER
    /// Trace logging level when cluster tracing is compiled in.
    public var traceLogLevel: Logger.Level? = .warning
    #else
    /// Optional trace logging level when cluster tracing is not compiled in.
    public var traceLogLevel: Logger.Level?
    #endif

    /// クラスタ内のloggerに適用する設定。
    public var logging: LoggingSettings = .default {
        didSet {
            self.swim.logger = self.logging.baseLogger
        }
    }

    /// クラスタ内のmetricsに適用する設定。
    public var metrics: MetricsSettings = .default(rootName: nil)

    /// Internal only; Instrumentation configuration, allowing to set instrumentation objects to be called by actor
    /// system internals, for purpose of metrics collection etc.
    internal var instrumentation: InstrumentationSettings = .default

    /// Installs a global backtrace (on fault) pretty-print facility upon actor system start.
    @available(
        *,
        deprecated,
        message: """
            Backtrace will not longer be offered by the actor system by default, \
            and has to be depended on by end-users
            """
    )
    public var installSwiftBacktrace: Bool = false

    /// 内部thread poolのthread数。
    public var threadPoolSize: Int = ProcessInfo.processInfo.activeProcessorCount

    /// システム名と接続先を指定して設定を作る。
    public init(
        name: String,
        host: String = Default.bindHost,
        port: Int = Default.bindPort,
        tls: TLSConfiguration? = nil
    ) {
        self.init(endpoint: Cluster.Endpoint(systemName: name, host: host, port: port), tls: tls)
    }

    /// Endpointを指定して設定を作り、新しいnode identifierを割り当てる。
    public init(endpoint: Cluster.Endpoint, tls: TLSConfiguration? = nil) {
        self.endpoint = endpoint
        self.nid = Cluster.Node.Identifier.random()
        self.tls = tls
        self.swim = SWIM.Settings()
        self.swim.unreachability = .enabled
        if !endpoint.systemName.isEmpty {
            self.metrics.systemName = endpoint.systemName
            self.swim.metrics.systemName = endpoint.systemName
        }
        self.swim.metrics.labelPrefix = "cluster.swim"
        self.discovery = nil
        self.serialization.localNode = self.bindNode
    }

    /// Unless the `eventLoopGroup` property is set, this function is used to create a new event loop group
    /// for the underlying NIO pipelines.
    public func makeDefaultEventLoopGroup() -> EventLoopGroup {
        MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)  // share pool with others
    }

    internal mutating func enable(host: String, port: Int) {
        self.enabled = true
        self.bindHost = host
        self.bindPort = port
    }

    internal mutating func disable() {
        self.enabled = false
    }
}
