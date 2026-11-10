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

import CoreMetrics
import Logging

extension OperationLogClusterReceptionist {
    internal func onClusterEvent(_ context: ActorContext<Message>, event: Cluster.Event) {
        switch event {
        case .snapshot(let snapshot):
            let diff: MembershipDiff = Cluster.Membership.difference(from: .empty, to: snapshot)
            guard !diff.changes.isEmpty else {
                return  // empty changes, nothing to act on
            }
            context.log.debug(
                "Changes from initial snapshot, applying one by one",
                metadata: [
                    "membership/changes": "\(diff.changes)"
                ]
            )
            for change in diff.changes {
                self.onClusterEvent(context, event: .membershipChange(change))
            }

        case .membershipChange(let change):
            guard let effectiveChange = self.membership.applyMembershipChange(change) else {
                return
            }

            if effectiveChange.previousStatus == nil {
                // a new member joined, let's store and contact its receptionist
                self.onNewClusterMember(context, change: effectiveChange)
            } else if effectiveChange.status.isAtLeast(.down) {
                // a member was removed, we should prune it from our observations
                self.pruneClusterMember(context, removedNode: effectiveChange.node)
            }

        case .leadershipChange, .reachabilityChange:
            return  // we ignore those

        case .nonExhaustive:
            context.log.error("Received Cluster.Event [\(event)]. This should not happen, please file an issue.")
        }
    }

    internal func onNewClusterMember(
        _ context: ActorContext<OperationLogClusterReceptionist.Message>,
        change: Cluster.MembershipChange
    ) {
        guard change.previousStatus == nil else {
            return  // not a new member
        }

        guard change.node != context.system.cluster.node else {
            return  // no need to contact our own node, this would be "us"
        }

        context.log.debug("New member, contacting its receptionist: \(change.node)")

        // resolve receptionist on the other node, so we can stream our registrations to it
        let remoteReceptionistAddress: ActorID = ActorID.actorRefReceptionist(on: change.node, for: .actorRefs)
        let remoteReceptionist: ActorRef<Message> = context.system.resolve(
            context: .init(id: remoteReceptionistAddress, system: context.system)
        )

        // we noticed a new member, and want to offer it our information right away

        // store the remote receptionist and replayer, it shall always use the same replayer
        let replayer: OpLog<ReceptionistOp>.Replayer = self.ops.replay(from: .beginning)
        self.peerReceptionistReplayers[remoteReceptionist] = replayer

        self.replicateOpsBatch(context, to: remoteReceptionist)
    }

    internal func pruneClusterMember(
        _ context: ActorContext<OperationLogClusterReceptionist.Message>,
        removedNode: Cluster.Node
    ) {
        context.log.trace("Pruning cluster member: \(removedNode)")
        let terminatedReceptionistAddress: ActorID = ActorID.actorRefReceptionist(on: removedNode, for: .actorRefs)
        let equalityHackPeerRef: ActorRef<Message> = ActorRef<Message>(
            .deadLetters(.init(context.log, id: terminatedReceptionistAddress, system: nil))
        )

        guard self.peerReceptionistReplayers.removeValue(forKey: equalityHackPeerRef) != nil else {
            // we already removed it, so no need to keep scanning for it.
            // this could be because we received a receptionist termination before a node down or vice versa.
            //
            // although this should not happen and may indicate we got a Terminated for an address twice?
            return
        }

        // clear observations; we only get them directly from the origin node, so since it has been downed
        // we will never receive more observations from it.
        _ = self.observedSequenceNrs.pruneReplica(.actorID(terminatedReceptionistAddress))
        _ = self.appliedSequenceNrs.pruneReplica(.actorID(terminatedReceptionistAddress))

        // clear state any registrations still lingering about the now-known-to-be-down node
        let pruned: ReceptionistStorage.PrunedNodeDirective = self.storage.pruneNode(removedNode)
        for key in pruned.keys {
            self.publishListings(context, forKey: key, to: pruned.peersToNotify(key))
        }
    }
}
