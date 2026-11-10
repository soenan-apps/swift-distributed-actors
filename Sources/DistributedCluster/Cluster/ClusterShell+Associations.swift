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

import CoreMetrics
import DistributedActorsConcurrencyHelpers
import Logging
import NIO
import SWIM

extension ClusterShell {

    /// Final action performed when severing ties with another node.
    /// We "Shoot The Other Node ..." (STONITH) in order to let it know as soon as possible (i.e. directly, without
    /// waiting for gossip to reach it).
    ///
    /// This is a best-effort message; as we may be downing it because we cannot communicate with it after all, in such
    /// situation (and many others)
    /// the other node would never receive this direct terminate/down eager "gossip." We hope it will either receive the
    /// down via some means, or determine
    /// by itself that it should down itself.
    internal static func shootTheOtherNodeAndCloseConnection(
        system: ClusterSystem,
        targetNodeAssociation: Association
    ) {
        let log: Logger = system.log
        let remoteNode: Cluster.Node = targetNodeAssociation.remoteNode
        traceLog_Remote(
            system.cluster.node,
            """
            Finish terminate association [\(remoteNode)]: \
            Shooting the other node a direct .gossip to down itself
            """,
            file: #fileID,
            line: #line
        )

        // On purpose use the "raw" RemoteControl to send the message -- this way we avoid the association lookup (it
        // may already be removed),
        // and directly hit the channel. It is also guaranteed that the message is flushed() before we close it in the
        // next line.
        let shootTheOtherNodePromise: EventLoopPromise<Void> = system.eventLoopGroup.next().makePromise(of: Void.self)

        let ripMessage: Payload = Payload(
            payload: .message(Self.Message.inbound(.restInPeace(remoteNode, from: system.cluster.node)))
        )
        targetNodeAssociation.sendUserMessage(
            envelope: ripMessage,
            recipient: .clusterShell(on: remoteNode),
            promise: shootTheOtherNodePromise
        )

        let shootTheNodeWriteTimeout: NIO.TimeAmount = .seconds(10)
        system.eventLoopGroup.next().scheduleTask(deadline: NIODeadline.now() + shootTheNodeWriteTimeout) {
            shootTheOtherNodePromise.fail(
                TimeoutError(
                    message: "Timed out writing final STONITH to \(remoteNode), should close forcefully.",
                    timeout: .seconds(10)
                )
            )
        }

        shootTheOtherNodePromise.futureResult.map { _ in
            // Only after the write has completed, we close the channel
            targetNodeAssociation.terminate(system)
        }.whenComplete { reason in
            log.trace("Closed connection with \(remoteNode): \(reason)")
        }
    }

    internal func getAnyExistingAssociation(with endpoint: Cluster.Endpoint) -> Association? {
        self.associationsLock.withLock {
            // this used to be separated in the State keeping them by Node and here we kept by unique though that caused
            // other challenges
            self.associations.first { $0.key.endpoint == endpoint }?.value
        }
    }

    internal func getExistingAssociationTombstone(with node: Cluster.Node) -> Association.Tombstone? {
        self.associationsLock.withLock {
            self.associationTombstones[node]
        }
    }

    /// Get an existing association or ensure that a new one shall be stored and joining kicked off if the target node
    /// was not known yet.
    /// Safe to concurrently access by privileged internals directly
    internal func getEnsureAssociation(with node: Cluster.Node) -> StoredAssociationState {
        self.associationsLock.withLock {
            if let tombstone = self.associationTombstones[node] {
                return .tombstone(tombstone)
            }
            if let existing = self.associations[node] {
                return .association(existing)
            }
            let association: Association = Association(selfNode: self.selfNode, remoteNode: node)
            self.associations[node] = association

            // Allocate before initiating the handshake so concurrent sends share this association's queue.
            self.ref.tell(.command(.handshakeWithSpecific(node)))

            return .association(association)
        }
    }

    internal func getSpecificExistingAssociation(with node: Cluster.Node) -> Association? {
        self.associationsLock.withLock {
            self.associations[node]
        }
    }

    /// To be invoked by cluster shell whenever handshake is accepted, creating a completed association.
    /// Causes messages to be flushed onto the new associated channel.
    internal func completeAssociation(_ associated: ClusterShellState.AssociatedDirective) throws {
        // 1) Complete and store the association
        try self.associationsLock.withLockVoid {
            let node: Cluster.Node = associated.handshake.remoteNode
            let association: Association =
                self.associations[node]
                ?? Association(selfNode: associated.handshake.localNode, remoteNode: node)

            try association.completeAssociation(handshake: associated.handshake, over: associated.channel)

            self.associations[node] = association
        }

        // 2) Ensure the failure detector knows about this node
        Task {
            await self.activeSWIMActor.whenLocal { localSWIMActor in
                localSWIMActor.monitor(node: associated.handshake.remoteNode)
            }
        }
    }

    /// Performs all cleanups related to terminating an association:
    /// - cleans the Shell local Association cache
    /// - sets a tombstone for the now-tombstone Cluster.Node
    /// - ensures node is at least .down in the Membership
    ///
    /// Can be invoked as result of a direct .down being issued, or because of a node replacement happening.
    internal func terminateAssociation(
        _ system: ClusterSystem,
        state: inout ClusterShellState,
        _ remoteNode: Cluster.Node
    ) {
        traceLog_Remote(
            system.cluster.node,
            "Terminate association with [\(remoteNode)]",
            file: #fileID,
            line: #line
        )

        let removedAssociationOption: Association? = self.associationsLock.withLock {
            // tombstone the association in the shell immediately.
            // No more message sends to the system will be possible.
            traceLog_Remote(
                system.cluster.node,
                "Finish terminate association [\(remoteNode)]: Stored tombstone",
                file: #fileID,
                line: #line
            )
            self.associationTombstones[remoteNode] = Association.Tombstone(remoteNode, settings: system.settings)
            return self.associations.removeValue(forKey: remoteNode)
        }

        guard let removedAssociation = removedAssociationOption else {
            system.log.debug("Attempted to terminate non-existing association [\(reflecting: remoteNode)].")
            return
        }

        system.log.warning("Terminate existing association [\(reflecting: remoteNode)].")

        // notify the failure detector, that we shall assume this node as dead from here on.
        // it's gossip will also propagate the information through the cluster
        traceLog_Remote(
            system.cluster.node,
            "Finish terminate association [\(remoteNode)]: Notifying SWIM, .confirmDead",
            file: #fileID,
            line: #line
        )
        system.log.warning("Confirm .dead to underlying SWIM, node: \(reflecting: remoteNode)")
        self.activeSWIMActor.confirmDead(node: remoteNode)

        // it is important that we first check the contains; as otherwise we'd re-add a .down member for what was
        // already removed (!)
        if state.membership.contains(remoteNode) {
            // Ensure to down the "previous" member in the Membership, it is not even .leaving anymore.
            if state.membership.mark(remoteNode, as: .down) == nil {
                // it was already removed, nothing to do
                state.log.trace(
                    "Terminate association with \(reflecting: remoteNode), yet node not in membership already?",
                    metadata: [
                        "cluster/membership": .string("\(pretty: state.membership)")
                    ]
                )
            }
        }

        // The last thing we attempt to do with the other node is to shoot it,
        // in case it's a "zombie" that still may receive messages for some reason.
        Self.shootTheOtherNodeAndCloseConnection(system: system, targetNodeAssociation: removedAssociation)
    }

    /// For testing only.
    internal func associatedNodes() -> Set<Cluster.Node> {
        self.associationsLock.withLock {
            Set(self.associations.keys)
        }
    }
}
