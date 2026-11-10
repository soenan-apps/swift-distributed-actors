// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
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

@testable import DistributedCluster

// usual reminder that Swift Distributed Actors is not inherently "client/server" once associated, only the handshake is
internal enum HandshakeSide: String {
    case client = "client"
    case server = "server"
}

extension ClusterShellState {
    internal static func makeTestMock(
        side: HandshakeSide, configureSettings: ((inout ClusterSystemSettings) -> Void)?
    ) -> ClusterShellState {
        var settings: ClusterSystemSettings = ClusterSystemSettings(
            endpoint: Cluster.Endpoint(
                systemName: "MockSystem",
                host: "127.0.0.1",
                port: 7_337
            )
        )
        configureSettings?(&settings)
        let log: Logger = Logger(label: "handshake-\(side)")

        let node: Cluster.Node = Cluster.Node(systemName: "Test", host: "127.0.0.1", port: 7_337, nid: .random())
        return ClusterShellState(
            settings: settings,
            channel: EmbeddedChannel(),
            events: ClusterEventStream(),  // this event stream does nothing
            gossiperControl: GossiperControl(
                ActorRef(.deadLetters(.init(log, id: .deadLettersRef(on: node), system: nil)))
            ),
            log: log
        )
    }
}
