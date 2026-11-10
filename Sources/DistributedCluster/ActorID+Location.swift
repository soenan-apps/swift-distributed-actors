// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

extension ActorID {
    /// Local root (also known as: "/") actor address.
    /// Only to be used by the "/" root "actor"
    internal static func localRoot(on node: Cluster.Node) -> ActorID {
        ActorPath.root.makeLocalID(on: node, incarnation: .wellKnown)
    }

    /// Local dead letters address.
    internal static func deadLettersRef(on node: Cluster.Node) -> ActorID {
        ActorPath.deadLettersRef.makeLocalID(on: node, incarnation: .wellKnown)
    }
}

extension ActorID {
    /// このIDを現在のシステムがローカルとして扱うかどうか。
    public var isLocal: Bool {
        switch self.location {
        case .local:
            return true

        default:
            return false
        }
    }

    /// このIDを現在のシステムがリモートとして扱うかどうか。
    public var isRemote: Bool {
        !self.isLocal
    }

    /// 所属ノードと識別情報を保ち、リモートとして扱うコピーを返す。
    public var asRemote: Self {
        var remote: Self = self
        remote.location = .remote(remote.node)
        return remote
    }

    /// 所属ノードと識別情報を保ち、ローカルとして扱うコピーを返す。
    public var asLocal: Self {
        var local: Self = self
        local.location = .local(self.node)
        return local
    }
}
