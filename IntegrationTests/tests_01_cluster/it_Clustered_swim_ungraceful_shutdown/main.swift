// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedCluster

internal var args: [String] = CommandLine.arguments

args.removeFirst()

guard args.count >= 2, let bindPort = Int(args[1]) else {
    fatalError("Node name and bind port must be provided")
}

internal let kNodeName: String = args[0]

print("Binding to port \(bindPort)")

internal let kSystem: ClusterSystem = await ClusterSystem(kNodeName) { settings in
    settings.logging.logLevel = .info

    settings.enabled = true
    settings.bindPort = bindPort

    settings.swim.probeInterval = .milliseconds(300)
    settings.swim.pingTimeout = .milliseconds(100)
}

internal let kRef: ActorRef<Cluster.Event> = try kSystem.spawn("streamWatcher", .receive { context, event in
    context.log.info("Event: \(event)")
    return .same
})

kSystem.cluster.events.subscribe(kRef)

if args.count >= 4, let joinPort = Int(args[3]) {
    let joinHost: String = args[2]
    print("Joining node \(joinHost):\(joinPort)")
    kSystem.cluster.join(host: joinHost, port: joinPort)
}

ClusterThread.sleep(.seconds(120))
