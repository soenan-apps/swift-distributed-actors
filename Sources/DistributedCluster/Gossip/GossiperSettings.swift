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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Gossiper Settings

internal struct GossiperSettings {
    internal enum GossipSpreadingStyle {
        /// Sends gossip without requiring acknowledgements.
        case unidirectional

        /// Sends gossip using ask and expects acknowledgements.
        case acknowledged(timeout: Duration)
    }

    internal enum PeerDiscovery {
        /// Peers have to be manually introduced by calling `control.introduce()` on to the gossiper.
        /// This gives full control about when a peer should join the gossip group, however usually is not necessary
        /// Cluster events can instead introduce operational members automatically.
        case manuallyIntroduced

        /// Automatically register this gossiper and subscribe for any others identifying under the same
        /// `Reception.Key<GossipShell<Gossip, Acknowledgement>.Message>(id)`.
        case fromReceptionistListing(id: String)

        /// Discovers reachable members that have reached the configured status.
        ///
        /// Note that by default `.leaving`, `.down` and `.removed` members are NOT added to the gossip group,
        /// even if they were never contacted by this gossiper before.
        case onClusterMember(atLeast: Cluster.MemberStatus, resolve: (Cluster.Member) -> AddressableActorRef)
    }

    /// Interval at which gossip rounds should proceed.
    ///
    /// - SeeAlso: `intervalRandomFactor`
    internal var interval: Duration

    /// Adds a random factor to the gossip interval, which is useful to avoid an entire cluster ticking "synchronously"
    /// at the same time, causing spikes in gossip traffic (as all nodes decide to gossip in the same second).
    ///
    /// - example: A random factor of `0.5` results in backoffs between 50% below and 50% above the base interval.
    /// - warning: MUST be between: `<0; 1>` (inclusive)
    internal var intervalRandomFactor: Double = 0.2 {
        willSet {
            precondition(newValue >= 0, "intervalRandomFactor MUST BE >= 0, was: \(newValue)")
            precondition(newValue <= 1, "intervalRandomFactor MUST BE <= 1, was: \(newValue)")
        }
    }

    internal var effectiveInterval: Duration {
        let baseInterval: Duration = self.interval
        let randomizeMultiplier: Double = Double.random(
            in: (1 - self.intervalRandomFactor)...(1 + self.intervalRandomFactor)
        )
        return baseInterval * randomizeMultiplier
    }

    /// Hints the Gossiper at weather or not acknowledgments are expected or not.
    ///
    /// If a gossiper which does not expect acknowledgements would be about to send an ack, a warning will be logged.
    internal var style: GossipSpreadingStyle

    /// How the gossiper should discover peers to gossip with.
    internal var peerDiscovery: PeerDiscovery = .manuallyIntroduced
}
