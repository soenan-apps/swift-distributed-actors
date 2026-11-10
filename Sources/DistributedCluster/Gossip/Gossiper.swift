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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Gossiper

/// A generalized Gossiper which can interpret a `GossipLogic` provided to it.
///
/// It encapsulates multiple error prone details surrounding implementing gossip mechanisms,
/// such as peer monitoring and managing cluster events and their impact on peers.
///
/// It can automatically discover new peers as new members join the cluster using the `Receptionist`.
///
/// - SeeAlso: [Gossiping in Distributed Systems](https://www.distributed-systems.net/my-data/papers/2007.osr.pdf)
internal enum Gossiper {
    /// Spawns a gossip actor, that will periodically gossip with its peers about the provided payload.
    internal static func spawn<Logic, Envelope, Acknowledgement>(
        _ context: ActorRefFactory,
        name naming: ActorNaming,
        settings: GossiperSettings,
        props: Props = .init(),
        makeLogic: @escaping (Logic.Context) -> Logic
    ) throws -> GossiperControl<Envelope, Acknowledgement>
    where Logic: GossipLogic, Logic.Gossip == Envelope, Logic.Acknowledgement == Acknowledgement {
        let ref: GossipShell<Envelope, Acknowledgement>.Ref = try context.spawn(
            naming,
            GossipShell<Envelope, Acknowledgement>(settings: settings, makeLogic: makeLogic).behavior,
            props: props,
            file: #filePath,
            line: #line
        )
        return GossiperControl(ref)
    }
}
