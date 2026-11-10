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

internal struct GossipLogicContext<Envelope: Codable, Acknowledgement: Codable> {
    /// Identifier associated with this gossip logic.
    ///
    /// Many gossipers only use a single identifier (and logic),
    /// however some may need to manage gossip rounds for specific identifiers independently.
    internal let gossipIdentifier: GossipIdentifier

    private let gossiperContext: ActorContext<GossipShell<Envelope, Acknowledgement>.Message>

    /// May be used as equivalent of "myself" for purposes of logging.
    ///
    /// Should not be used to arbitrarily allow sending messages to the gossiper from gossip logics,
    /// which is why it is only an address and not full ActorRef to the gossiper.
    internal var gossiperAddress: ActorID {
        self.gossiperContext.myself.id
    }

    /// Logger associated with the owning `Gossiper`.
    ///
    /// Has the `gossip/identifier` of this gossip logic stored as metadata automatically.
    internal var log: Logger {
        var logger: Logger = self.gossiperContext.log
        logger[metadataKey: "gossip/identifier"] = "\(self.gossipIdentifier)"
        return logger
    }

    internal var system: ClusterSystem {
        self.gossiperContext.system
    }

    internal init(
        ownerContext: ActorContext<GossipShell<Envelope, Acknowledgement>.Message>,
        gossipIdentifier: GossipIdentifier
    ) {
        self.gossiperContext = ownerContext
        self.gossipIdentifier = gossipIdentifier
    }
}
