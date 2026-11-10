// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

extension ClusterSystem {
    /// クラスタ内のActorをノードとincarnationで識別する値。
    /// ローカル・リモートの区別は実行時の最適化であり、同一性には影響しない。
    /// Actorを保持せずにIDだけを保存できるため、終了済みのActorも表現できる。
    /// metadataは付随情報を保持し、シリアライズ時には所属ノードも伝える。
    public struct ActorID: @unchecked Sendable {
        /// 実行時の位置情報。ユーザがローカルであることに依存しないよう内部に限定する。
        @usableFromInline internal var location: ActorLocation

        /// The unique node on which the actor identified by this identity is located.
        public var node: Cluster.Node {
            switch self.location {
            case let .local(node):
                return node

            case let .remote(node):
                return node
            }
        }

        #if DEBUG
        internal var debugID: UUID = UUID()
        #endif

        /// Actorに付随するタグ。個々のタグの配送範囲はActorMetadataの契約に従う。
        public var metadata: ActorMetadata {
            self.context.metadata
        }

        /// Internal "actor context" which is used as storage for additional cluster actor features, such as watching.
        internal var context: DistributedActorContext

        /// Underlying path representation, not attached to a specific Actor instance.
        public var path: ActorPath {
            get {
                guard let storedPath = metadata.path else {
                    fatalError(
                        """
                        ActorTags.path was not set on \(self.incarnation)! \
                        NOTE THAT PATHS ARE TO BECOME OPTIONAL!!!
                        """
                    )
                }
                return storedPath
            }
            set {
                self.metadata[ActorMetadataKeys.defaultInstance.path.id] = newValue
            }
        }

        /// Returns the name of the actor represented by this path.
        /// This is equal to the last path segments string representation.
        public var name: String {
            self.path.name
        }

        /// Uniquely identifies the specific "incarnation" of this actor.
        public let incarnation: ActorIncarnation

        internal var withoutLifecycle: Self {
            var copy: Self = self
            copy.context = .init(
                lifecycle: nil,
                remoteCallInterceptor: nil,
                metadata: self.metadata
            )
            return copy
        }

        /// lifecycleを維持し、metadataとremote call interceptorを持たないコピーを返す。
        public var withoutMetadata: Self {
            var copy: Self = self
            copy.context = .init(
                lifecycle: self.context.lifecycle,
                remoteCallInterceptor: nil
            )
            return copy
        }

        internal init(local node: Cluster.Node, path: ActorPath?, incarnation: ActorIncarnation) {
            self.context = .init(lifecycle: nil, remoteCallInterceptor: nil)
            self.location = .local(node)
            self.incarnation = incarnation
            if let path {
                self.context.metadata.path = path
            }
            traceLog_DeathWatch("Made ID: \(self)", file: #fileID, line: #line)
        }

        internal init(remote node: Cluster.Node, path: ActorPath?, incarnation: ActorIncarnation) {
            self.context = .init(lifecycle: nil, remoteCallInterceptor: nil)
            self.location = .remote(node)
            self.incarnation = incarnation
            if let path {
                self.context.metadata.path = path
            }
            traceLog_DeathWatch("Made ID: \(self)", file: #fileID, line: #line)
        }

        /// 指定したActor型とincarnationから、リモートIDを構築する。
        public init<Act>(remote node: Cluster.Node, type: Act.Type, incarnation: ActorIncarnation)
        where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
            self.context = .init(lifecycle: nil, remoteCallInterceptor: nil)
            self.location = .remote(node)
            self.incarnation = incarnation
            if let mangledName = _mangledTypeName(type) {
                self.context.metadata.type = .init(mangledName: mangledName)
            }
            traceLog_DeathWatch("Made ID: \(self)", file: #fileID, line: #line)
        }

        internal init<Act>(
            local node: Cluster.Node,
            type: Act.Type,
            incarnation: ActorIncarnation,
            context: DistributedActorContext
        )
        where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
            self.context = context
            self.location = .local(node)
            self.incarnation = incarnation
            if let mangledName = _mangledTypeName(type) {
                self.context.metadata.type = .init(mangledName: mangledName)
            }
            traceLog_DeathWatch("Made ID: \(self)", file: #fileID, line: #line)
        }

        internal init<Act>(
            remote node: Cluster.Node,
            type: Act.Type,
            incarnation: ActorIncarnation,
            context: DistributedActorContext
        )
        where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
            self.context = context
            self.location = .remote(node)
            self.incarnation = incarnation
            if let mangledName = _mangledTypeName(type) {
                self.context.metadata.type = .init(mangledName: mangledName)
            }
            traceLog_DeathWatch("Made ID: \(self)", file: #fileID, line: #line)
        }
    }
}
