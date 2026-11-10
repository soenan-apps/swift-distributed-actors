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

/// Drives cluster connections and membership state machines.
internal class ClusterShell {
    internal typealias Ref = ActorRef<ClusterShell.Message>

    internal enum StoredAssociationState {
        /// An existing (ready or being associated association) which can be used to send (or buffer buffer until
        /// associated/terminated)
        case association(Association)
        /// The association with the node existed, but is now a tombstone and no more messages shall be send to it.
        case tombstone(Association.Tombstone)
    }

    // Due to lack of Union Types, we have to emulate them
    internal enum Message: Codable {
        // The external API, exposed to users of the ClusterShell
        case command(CommandMessage)
        // The external API, exposed to users of the ClusterShell to query for state
        case query(QueryMessage)
        /// Messages internally driving the state machines; timeouts, network inbound events etc.
        case inbound(InboundMessage)
        /// Used to request making a change to the membership owned by the ClusterShell;
        /// Issued by downing or leader election and similar facilities. Thanks to centralizing the application of
        /// changes,
        /// we can ensure that a ``Cluster/Event`` is signalled only once, and only when it is really needed.
        /// E.g. signalling a down twice for whatever reason, needs not be notified two times to all subscribers of
        /// cluster events.
        ///
        /// If the passed in event applied to the current membership is an effective change, the change will be
        /// published using the `system.cluster.events`.
        case requestMembershipChange(Cluster.Event)
        /// Gossiping is handled by /system/cluster/gossip, however acting on it still is our task,
        /// thus the gossiper forwards gossip whenever interesting things happen ("more up to date gossip")
        /// to the shell, using this message, so we may act on it -- e.g. perform leader actions or change membership
        /// that we store.
        case gossipFromGossiper(Cluster.MembershipGossip)
    }

    // this is basically our API internally for this system
    internal enum CommandMessage: NotActuallyCodableMessage, SilentDeadLetter {
        /// Connect and handshake with remote `Node`, obtaining an `Cluster.Node` in the process.
        /// Once the handshake is completed, reply to `replyTo` with the handshake result, and also mark the unique node
        /// as `.joining`.
        ///
        /// If one is present, the underlying failure detector will be asked to monitor this node as well.
        case handshakeWith(Cluster.Endpoint)
        case handshakeWithSpecific(Cluster.Node)
        case retryHandshake(HandshakeStateMachine.InitiatedState)

        case failureDetectorReachabilityChanged(Cluster.Node, Cluster.MemberReachability)

        /// Used to signal a "down was issued" either by the user, or another part of the system.
        case downCommand(Cluster.Endpoint)
        /// Used to signal a "down was issued" either by the user, or another part of the system.
        case downCommandMember(Cluster.Member)
        case shutdown(BlockingReceptacle<Void>)
        case cleanUpAssociationTombstones
    }

    internal enum QueryMessage: NotActuallyCodableMessage {
        case associatedNodes(ActorRef<Set<Cluster.Node>>)
        case currentMembership(ActorRef<Cluster.Membership>)
    }

    internal enum InboundMessage {
        case handshakeOffer(
            Wire.HandshakeOffer,
            channel: Channel,
            handshakeReplyTo: EventLoopPromise<Wire.HandshakeResponse>
        )
        case handshakeAccepted(Wire.HandshakeAccept, channel: Channel)
        case handshakeRejected(Wire.HandshakeReject)
        case handshakeFailed(Cluster.Endpoint, Error)
        /// This message is used to avoid "zombie nodes" which are known as .down by other nodes, but still stay online.
        /// It is sent as a best-effort by any node which terminates the connection with this node, e.g. if it knows
        /// already
        /// about this node being `.down` yet it still somehow attempts to communicate with the another node.
        ///
        /// Upon receipt, should be interpreted as having to immediately down myself.
        case restInPeace(Cluster.Node, from: Cluster.Node)
    }

    internal enum HandshakeResult: Equatable, NotActuallyCodableMessage {
        case success(Cluster.Node)
        case failure(HandshakeStateMachine.HandshakeConnectionError)
    }

    internal static let naming: ActorNaming = ActorNaming.unique("cluster")

    internal static let gossipID: StringGossipIdentifier = "membership"

    internal var selfNode: Cluster.Node {
        self.settings.bindNode
    }

    internal let settings: ClusterSystemSettings

    // ~~~~~~ HERE BE DRAGONS, shared concurrently modified concurrent state ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    // We do this to avoid "looping" any initial access of an actor ref through the cluster shell's mailbox
    // which would cause more latency to obtaining the association. refs cache the remote control once they have
    // obtained it.

    internal let associationsLock: Lock

    /// Used by remote actor refs to obtain associations
    /// - Protected by: `associationsLock`
    internal var associations: [Cluster.Node: Association]
    /// Node tombstones are kept here in order to avoid attempting to associate if we get a reference to such node,
    /// which would normally trigger an `ensureAssociated`.
    /// - Protected by: `associationsLock`
    internal var associationTombstones: [Cluster.Node: Association.Tombstone]

    /// For testing only.
    /// Safe to concurrently access by privileged internals.
    internal var testingAssociations: [Association] {
        self.associationsLock.withLock {
            [Association](self.associations.values)
        }
    }

    /// For testing only.
    /// Safe to concurrently access by privileged internals.
    internal var testingAssociationTombstones: [Association.Tombstone] {
        self.associationsLock.withLock {
            [Association.Tombstone](self.associationTombstones.values)
        }
    }

    // ~~~~~~ END OF HERE BE DRAGONS, shared concurrently modified concurrent state ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    // `serializationPoolStorage` is only used when `start()` is invoked, and there it is set immediately as well
    // any earlier access to the pool is a bug (in our library) and must be treated as such.
    internal var serializationPoolStorage: SerializationPool?
    internal var serializationPool: SerializationPool {
        guard let pool = self.serializationPoolStorage else {
            fatalError(
                """
                BUG! Tried to access serializationPool on \(self) and it was nil! \
                Please report this on the issue tracker.
                """
            )
        }
        return pool
    }

    internal var swimShell: SWIMActor?

    internal var clusterEventsStorage: ClusterEventStream?

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Cluster Shell, reference used for issuing commands to the cluster

    internal let refLock: Lock = Lock()

    internal var refStorage: ClusterShell.Ref?
    internal var ref: ClusterShell.Ref {
        self.refLock.lock()
        defer { refLock.unlock() }

        // since this is initiated during system startup, nil should never happen
        guard let reference = self.refStorage else {
            return fatalErrorBacktrace(
                """
                Accessing ClusterShell.ref failed, was nil! \
                This should never happen as access should only happen after start() was invoked.
                """,
                file: #file,
                line: #line
            )
        }
        return reference
    }

    internal let props: Props =
        .init()
        .supervision(strategy: .escalate)
        .asWellKnown

    internal var activeSWIMActor: SWIMActor {
        guard let actor = self.swimShell else {
            preconditionFailure("ClusterShell SWIM actor accessed before start completed")
        }
        return actor
    }

    internal var clusterEvents: ClusterEventStream {
        guard let events = self.clusterEventsStorage else {
            preconditionFailure("ClusterShell events accessed before start")
        }
        return events
    }

    internal init(settings: ClusterSystemSettings) {
        self.settings = settings
        self.associationsLock = Lock()
        self.associations = [:]
        self.associationTombstones = [:]

        // not enjoying this dance, but this way we can share the ClusterShell as the shell AND the container for the
        // ref.
        // the single thing in the class it will modify is the associations registry, which we do to avoid actor queues
        // when
        // remote refs need to obtain those
        //
        self.refStorage = nil
    }

    /// Actually starts the shell which kicks off binding to a port, and all further cluster work
    internal func start(system: ClusterSystem, clusterEvents: ClusterEventStream) async throws -> ActorRef<Message> {
        let instrumentation: InternalActorTransportInstrumentation =
            system.settings.instrumentation.makeActorTransportInstrumentation()
        self.serializationPoolStorage = try SerializationPool(
            settings: .default,
            serialization: system.serialization,
            instrumentation: instrumentation
        )
        self.clusterEventsStorage = clusterEvents

        let clusterRef: ClusterShell.Ref = try system.spawnSystemActor(Self.naming, self.bind(), props: self.props)
        self.refStorage = clusterRef

        await Props.$forSpawn.withValue(SWIMActor.props) {
            self.swimShell = await SWIMActor(settings: self.settings.swim, clusterRef: clusterRef, system: system)
        }

        return clusterRef
    }
}
