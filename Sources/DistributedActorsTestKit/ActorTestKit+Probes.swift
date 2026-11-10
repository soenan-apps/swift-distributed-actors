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
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

extension ActorTestKit {
    /// Spawn an `ActorTestProbe` which offers various assertion methods for actor messaging interactions.
    public func makeTestProbe<Message: Codable>(
        _ naming: ActorNaming? = nil,
        expecting _: Message.Type = Message.self,
        file _: StaticString = #filePath,
        line _: UInt = #line
    ) -> ActorTestProbe<Message> {
        self.makeProbesLock.lock()
        defer { self.makeProbesLock.unlock() }
        // we want to use our own sequence number for the naming here, so we make it here rather than let the
        // system use its own sequence number -- which should only be in use for the user actors.
        let name: String
        if let naming = naming {
            name = naming.makeName(&self.namingContext)
        } else {
            name = ActorTestProbe<Message>.naming.makeName(&self.namingContext)
        }

        return ActorTestProbe(
            { probeBehavior in

                var testProbeProps: Props = Props()
                #if SACT_PROBE_CALLING_THREAD
                testProbeProps.dispatcher = .callingThread
                #endif

                return try system.spawn(.init(unchecked: .unique(name)), probeBehavior, props: testProbeProps)
            },
            settings: self.settings,
            system: self.system
        )
    }

    /// Spawns an `ActorTestProbe` and immediately subscribes it to the system's cluster event stream.
    ///
    /// - Hint: Use `fishForMessages` and `fishFor` to filter expectations for specific events.
    public func spawnClusterEventStreamTestProbe(
        _ naming: ActorNaming? = nil,
        file _: String = #filePath,
        line _: UInt = #line,
        column _: UInt = #column
    ) async -> ActorTestProbe<Cluster.Event> {
        let eventStream: ClusterEventStream = self.system.cluster.events
        let probe: ActorTestProbe<Cluster.Event> = self.makeTestProbe(
            naming ?? ActorNaming.prefixed(with: "\(ClusterEventStream.self)-subscriberProbe"),
            expecting: Cluster.Event.self
        )
        await eventStream.subscribeAndWait(probe.ref)
        return probe
    }
}
