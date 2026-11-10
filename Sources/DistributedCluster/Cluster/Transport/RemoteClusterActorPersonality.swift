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

import Atomics

/// INTERNAL API: May change without any prior notice.
///
/// Represents a reference to a remote actor.
///
/// By owning a reference itself, no guarantees are given if the actor exists or even existed.
/// These guarantees are provided by ways of how this reference was obtained, e.g. if it was obtained
/// by being sent from a remote node, one can safely assume that the actor once existed.
/// Its current lifecycle state may already have changed when the reference arrives.
/// To observe its lifecycle, watch the actor through the usual death-watch protocol.
public final class RemoteClusterActorPersonality<Message: Codable> {
    internal let id: ActorID

    internal let clusterShell: ClusterShell
    internal let system: ClusterSystem

    internal var deadLetters: ActorRef<Message> {
        self.system.personalDeadLetters(recipient: self.id)
    }

    // Implementation notes:
    //
    // We hand out the ref before its connection is established and initiate handshakes asynchronously.
    // does not have to wait for the connection to be established, we can immediately return it, kick off handshakes,
    // and once the actor wants to send messages -- perhaps we've already completed the handshake and can directly send
    // messages onto the network.
    //
    // These associations are unique, and we must obtain "the" association that the cluster has established, or worse,
    // is in the middle of establishing. Associations handle sending messages "through" them, so as long as we get the
    // right one, message send order remains correct.
    //
    // The cluster actor maintains a lock protected, nonisolated, dictionary of unique nodes to associations.
    // We basically need to perform that lock+get(for:node)+unlock every time we'd like to send a message.
    // This would be terrible, because this associations dictionary is shared for all actors in the system -- so the
    // more actors, and more remote nodes the slower this access becomes (the lock is going to be highly contended).
    //
    // Problem:
    // - obtaining an association is accessing a highly contended lock
    // - messages may be sent to remote actors from *any* thread
    //
    // Observations:
    // - an association is always the same for a given actor reference (or rather, per unique node)
    // - no association is needed until the first message is sent to the remote actor
    //   - this enables us to kick off handshakes "in the background" and only once we try to send to it, we obtain it
    //     from the in-flight association dance the cluster is doing for us
    //
    // Solution:
    // - upon first message send, we don't have an association yet, so we attempt to load it from the cluster
    //   - lookup requires locking the association map
    //     - we may even end up causing an association to be created AFAIR.
    // - this will succeed, one way or another (a dead system, or handshake-in-flight, or ready association)
    // - store this association in a `ManagedAtomicLazyReference` and every subsequent time we want to send a message,
    //   we only pay the cost of this atomic read, rather than the expensive hashmap lookup and locking!
    private var cachedAssociation: ManagedAtomicLazyReference<Association>

    private var association: ClusterShell.StoredAssociationState {
        if let assoc = self.cachedAssociation.load() {
            return .association(assoc)
        }

        let associationState: ClusterShell.StoredAssociationState =
            self.clusterShell.getEnsureAssociation(with: self.id.node)
        switch associationState {
        case .association(let assoc):
            return .association(self.cachedAssociation.storeIfNilThenLoad(assoc))

        default:
            return associationState
        }
    }

    internal init(shell: ClusterShell, id: ActorID, system: ClusterSystem) {
        if !id.isRemote {
            let _: Void = fatalErrorBacktrace(
                "RemoteActorRef MUST be remote. ActorID was: \(id.detailedDescription)",
                file: #file,
                line: #line
            )
        }

        self.cachedAssociation = ManagedAtomicLazyReference()

        // Ensure we store as .remote, so printouts work as expected (and include the explicit address)
        var remoteID: ActorID = id
        remoteID.location = .remote(id.node)
        self.id = remoteID

        self.clusterShell = shell
        self.system = system
    }

    @usableFromInline
    internal func sendUserMessage(_ message: Message, file: String = #filePath, line: UInt = #line) {
        traceLog_Cell("RemoteActorRef(\(self.id)) sendUserMessage: \(message)", file: #fileID, line: #line)

        switch self.association {
        case .association(let association):
            association.sendUserMessage(envelope: Payload(payload: .message(message)), recipient: self.id)

        case .tombstone:
            self.deadLetters.tell(message, file: file, line: line)
        }
    }

    @usableFromInline
    internal func sendInvocation(_ invocation: InvocationMessage, file: String = #filePath, line: UInt = #line) {
        traceLog_Cell("RemoteActorRef(\(self.id)) sendInvocation: \(invocation)", file: #fileID, line: #line)

        switch self.association {
        case .association(let association):
            association.sendInvocation(invocation, recipient: self.id)

        case .tombstone:
            self.system.deadLetters.tell(DeadLetter(invocation, recipient: self.id), file: file, line: line)
        }
    }

    internal func sendSystemMessage(_ message: SystemMessages, file: String = #filePath, line: UInt = #line) {
        traceLog_Cell("RemoteActorRef(\(self.id)) sendSystemMessage: \(message)", file: #fileID, line: #line)

        switch self.association {
        case .association(let association):
            association.sendSystemMessage(message, recipient: self.id)

        case .tombstone:
            self.system.personalDeadLetters(recipient: self.id).tell(message, file: file, line: line)
        }
    }

    internal func unsafeAssumeCast<NewMessage: Codable>(
        to _: NewMessage.Type
    ) -> RemoteClusterActorPersonality<NewMessage> {
        RemoteClusterActorPersonality<NewMessage>(shell: self.clusterShell, id: self.id, system: self.system)
    }
}
