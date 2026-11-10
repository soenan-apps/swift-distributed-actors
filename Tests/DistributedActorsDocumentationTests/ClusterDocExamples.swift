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

// tag::imports[]

import DistributedCluster
import ServiceDiscovery
import XCTest

// end::imports[]

internal struct SomeGenericNode: Hashable {
    internal let host: String
    internal let port: Int
}

internal final class ClusterDocExamples: XCTestCase {
    private func example_receive_behavior() async {
        // tag::joining[]
        let system: ClusterSystem = await ClusterSystem("ClusterJoining") { settings in
            settings.enabled = true  // <1>
            // system will bind by default on `localhost:7337`
        }

        let otherNode: Cluster.Endpoint = Cluster.Endpoint(systemName: "ClusterJoining", host: "localhost", port: 8_228)
        system.cluster.join(endpoint: otherNode)  // <2>

        // end::joining[]
    }

    private func example_discovery_joining_seedNodes<Discovery: ServiceDiscovery>(
        _ discovery: Discovery
    ) async where Discovery.Service == String, Discovery.Instance == Cluster.Endpoint {
        // tag::discovery-joining-config[]
        let system: ClusterSystem = await ClusterSystem("DiscoveryJoining") { settings in
            settings.discovery = ServiceDiscoverySettings(
                discovery,
                service: "my-service"
            )
        }
        // end::discovery-joining-config[]
        _ = system
    }

    private func example_discovery_joining_seedNodes_2<Discovery: ServiceDiscovery>(
        _ discovery: Discovery
    ) async where Discovery.Service == String, Discovery.Instance == SomeGenericNode {
        // tag::discovery-joining-config-2[]
        let system: ClusterSystem = await ClusterSystem("DiscoveryJoining") { settings in
            settings.discovery = ServiceDiscoverySettings(
                discovery,  // <1>
                service: "my-service"
            ) { (instance: SomeGenericNode) -> Cluster.Endpoint in  // <2>
                Cluster.Endpoint(systemName: "", host: instance.host, port: instance.port)
            }
        }
        // end::discovery-joining-config-2[]
        _ = system
    }

    private func example_subscribe_events_apply() async throws {
        let system: ClusterSystem = await ClusterSystem("Sample")

        try system.spawn(.anonymous, .setup { context in
            // tag::subscribe-events-apply-general[]
            var membership: Cluster.Membership = .empty  // <1>

            let subRef: ActorRef<Cluster.Event> = context.subReceive(Cluster.Event.self) { event in  // <2>
                try membership.apply(event: event)  // <3>
                context.log.info("The most up to date membership is: \(membership)")
            }

            context.system.cluster.events.subscribe(subRef)  // <4>
            // end::subscribe-events-apply-general[]
            return .same
        })

        // tag::membership-snapshot[]
        let snapshot: Cluster.Membership = system.cluster.membershipSnapshot
        // end::membership-snapshot[]
        _ = snapshot  // silence not-used warning
    }
}
