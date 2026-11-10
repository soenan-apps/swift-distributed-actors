// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

/// The expected node does not currently host the requested singleton.
public struct SingletonNotFoundNoExpectedNode: Error {
    internal let id: String
    internal let node: Cluster.Node?

    internal init(id: String, _ node: Cluster.Node?) {
        self.id = id
        self.node = node
    }
}
