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

import DistributedActorsConcurrencyHelpers
import Logging
import NIO

extension ClusterShellState {
    internal var metadata: Logger.Metadata {
        [
            "membership/count": "\(String(describing: self.membership.count(atLeast: .joining)))"
        ]
    }

    internal func metadataForHandshakes(node: Cluster.Node?, error: Error?) -> Logger.Metadata {
        var values: Logger.Metadata = ["handshakes": "\(self.handshakes())"]
        if let peer = node {
            values["handshake/peer"] = "\(peer)"
        }
        if let failure = error {
            values["handshake/error"] = "\(failure)"
            values["handshake/errorType"] = "\(String(reflecting: type(of: failure)))"
        }
        return values
    }
}
