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

import Distributed

public struct RemoteCallError: DistributedActorSystemError, CustomStringConvertible {

    internal enum Reason {
        case clusterAlreadyShutDown
        case timedOut(ClusterSystem.CallID, TimeoutError)
        case invalidReply(ClusterSystem.CallID)
        case illegalReplyType(ClusterSystem.CallID, expected: Any.Type, got: Any.Type)
    }

    internal class Storage {
        internal let error: Reason
        internal let actorID: ActorID
        internal let target: RemoteCallTarget
        internal let file: String
        internal let line: UInt

        internal init(error: Reason, actorID: ActorID, target: RemoteCallTarget, file: String, line: UInt) {
            self.error = error
            self.actorID = actorID
            self.target = target
            self.file = file
            self.line = line
        }
    }

    internal let underlying: Storage

    public var description: String {
        "\(Self.self)(\(self.underlying.error), at: \(self.underlying.file):\(self.underlying.line))"
    }

    internal init(
        _ error: Reason,
        on actorID: ActorID,
        target: RemoteCallTarget,
        file: String = #fileID,
        line: UInt = #line
    ) {
        self.underlying = Storage(error: error, actorID: actorID, target: target, file: file, line: line)
    }

    internal init(_ error: Reason, file: String = #fileID, line: UInt = #line) {
        let actorID: ActorID = ActorID.deadLettersRef(
            on: Cluster.Node(protocol: "dead", systemName: "", host: "", port: 1, nid: .init(0))
        )
        let target: RemoteCallTarget = RemoteCallTarget("<unknown>")
        self.underlying = Storage(error: error, actorID: actorID, target: target, file: file, line: line)
    }

}
