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

// tag::imports[]

import ActorSingletonPlugin
import DistributedCluster

// end::imports[]

internal class ActorSingletonDocExamples {
    internal func example_ref() async throws {
        // tag::configure-system[]
        let system: ClusterSystem = await ClusterSystem("Sample") { settings in
            settings += ActorSingletonPlugin()  // <1>
        }
        // end::configure-system[]

        let singletonBehavior: Behavior<String> = .receive { context, name in
            context.log.info("Hello \(name)!")
            return .same
        }

        // tag::host-ref[]
        let singletonRef: ActorRef<String> = try system.singleton.host(
            String.self, name: "SampleSingleton", singletonBehavior
        )  // <1>
        singletonRef.tell("Jane Doe")  // <2>
        // end::host-ref[]

        // tag::proxy-ref[]
        let singletonProxyRef: ActorRef<String> = try system.singleton.ref(of: String.self, name: "SampleSingleton")
        singletonProxyRef.tell("Jane Doe")  // <1>
        // end::proxy-ref[]
    }
}
