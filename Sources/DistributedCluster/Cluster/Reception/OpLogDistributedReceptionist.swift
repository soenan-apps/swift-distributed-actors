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

import AsyncAlgorithms
import CoreMetrics
import Distributed
import Logging
import OrderedCollections

/// Cluster-aware (atomic broadcast style, push/pull-gossip) Receptionist implementation.
///
/// ### Intended usage / Optimization choices
/// This Receptionist implementation is optimized towards small to medium clusters (many tens of nodes) with much
/// actor churn,
/// rather than wide (hundreds of nodes) clusters with few registered actors. This implementation is guided by a
/// pragmatic view of
/// how most actor clusters operate, and also in face of the lack of built-in sharding or "virtual namespace" (yet),
/// which would normally be the way to handle millions of actors and tracking their locations (by "sharding" them and
/// moving and tracking them in groups).
///
/// The current implementation gives priority to streaming large amounts of refs between peers, without exceeding
/// a maximum batch size (thus avoiding too large messages, which would lead to head of line blocking of other messages,
/// including heartbeats etc).
///
/// We will re-consider and re-implement this receptionist given other requirements, or allow selecting its mode of
/// operation
/// in the future. E.g. a CRDT based receptionist would be preferable for wide clusters, as we can then avoid the
/// "origin"
/// peer having to stream all data to all peer receptionists. This approach however risks having to gossip a full state
/// when a new nodes join, or potentially for keys where we are unable to propagate _just deltas_. We hope that a future
/// CRDT replicator will be smart enough that we can replace this implementation without fear of too-large messages
/// being
/// put on the wire. We can achieve this in a number of ways (chunking full-state sync into a series of deltas anyway).
/// We will revisit this topic as we implement more advanced CRDT replicators.
///
/// ### Protocol
/// The protocol works on sending individual updates (operations, kind of like an operation based CRDT replicator
/// would),
/// rather than replicating "the entire set of actors registered under a key". The general implementation can be seen as
/// operation-log replication, where each receptionist "owns" its own log and others ask for "replays" of this log once
/// they notice they are behind (i.e. the last sequence nr they observed of the log is older than the latest available).
/// Once other receptionists notice (due to periodic ack gossip carrying "latest observed sequence nrs" of all other
/// receptionists)
/// a receptionist which's sequence nr is newer than they have observed from it, they initiate a pull by sending an
/// an `ack(until: latestAppliedSeqNrFromTarget)`. This causes the owner of the data to initiate a replay of the
/// operations
/// from the `ack.until` sequence nr.
///
/// There are a number of optimizations possible here which will be discussed below, though not all are implemented
/// today.
/// As usual in such schemes, log compaction becomes an important topic, though today we do not offer advanced
/// compaction yet.
///
/// The protocol can be visualized identical state machines acting on incoming operation logs (which inherently
/// separate,
/// and not affecting each other's), like so:
///
/// ```
///                                                     +---------------+
///                                                     |  rec B (@2)   |
/// // Upon receipt of (1), notice that should pull from A,
///                                                 +-->>  A@3,B@2,C@4  |
/// // since A@3 < A@10. It would send (ack <A@3,...>) to initiate a pull.
///      +--------------+       (1)                 |   +---------------+
///      |  rec A (@10) >>---(ack <B@2,...>)--------+
///      | A@10,B@2,C@4 <<---(ops [operation,operation,...] <>)---+   +---------------+
///      +--------------+       (2)                 |   |   rec C (@9)  |
/// // Caused a different `ack` from A, C knows that A is "behind",
///                                                 +--<< A@10,B@2,C@9  |
/// // and thus replicates its log to A by sending (2) PushOactorProps.
///                                                     +---------------+
/// // A will confirm and eventually the two peers are in-sync.
///
/// pull == ack - acknowledgements serve also as pull messages, if the ack-ed receptionist sees there is more data
/// to be sent, it does so
///
/// <v> - collection of "latest known" seqNr
/// operation  - versioned operation, when applying an operation we know up to which `X@n` n seqNr our state has
/// been forwarded to.
/// ```
///
/// #### Observation: Single-writer property of receptionist logs, as they are always "local to a receptionist":
/// Each receptionist only takes care of "their own" actors (i.e. on their own nodes), thus they are the authoritative
/// single-writer source of any information if a ref is registered or not. This is why we can rely on the 1:1 replaying
/// of events. Only a given node's receptionist takes care of the local register/remove, and later on gets pulled
/// for this
/// information by other receptionists -- the other peers will never remove an actor "owned" by another node, unless
/// that
/// node's receptionist tells them to do so. This also means we do not have to watch every single actor that is
/// spread throughout the cluster.
///
/// #### Observation: Fast streaming when needed / periodic small seqNr dissemination
/// It is worth noting that the protocol works effectively in "one mode," meaning that there is no explicit
/// "streaming from a peer"
/// and later "just gossiping" mode. The same message (`AckOps`) is used both to cause a pull, confirmation of
/// receipt of a `PushOps` as well as just spread observed sequence
/// number observations.
///
/// #### Optimization: "Blip" Registration Replication Avoidance
/// We define a "blip registration" as a registration of an actor, which immediately (or very quickly) after registering
/// terminates. It can be argued it is NOT useful to replicate the very existence of such short lived actor to other
/// peers,
/// as even if they'd act on the `register`, it'd be immediately followed by `remove` and/or a termination signal.
///
/// Thanks to the operation-log replication scheme, where we gossip pushes in "batch", we can notice such blips and
/// avoid pushing them
/// completely to other nodes. could also avoid sending to peers "blips" i.e. actors which register and immediately
/// terminate.
/// This remains to be debated, but one could argue it is NOT helpful to replicate such short lived ref at all,
/// if we already know it has terminated, thus we can avoid other nodes acting on this ref which they'd immediately
/// be notified has been terminated already.
///
/// The tradeoff here is that subscribing to a key may not be used to get "total number of actors that ever
/// registered under this key globally."
/// We believe this is a sensible tradeoff, as receptionists are only about current and live actors, it MAY however
/// cause weird initialization lockups,
/// where we "know" an actor should have spawned somewhere and registered, but we never see it -- this pattern seems
/// very fragile though so it seems
/// to make sense to discourage it.
///
/// ### Overall protocol outline
/// The goal of the protocol is to replicate a log of "ops" (`register` and `remove` operations), among all
/// receptionists within the cluster.
/// This is achieved by implementing atomic broadcast in the form of replay and re-delivery (pull/acknowledgement
/// driven) of these operations.
/// The operations are replicated directly from the "origin" receptionist ("the receptionist local to the actors
/// which register with it"),
/// to all other peer receptionists by means of them pulling for the ops, once they realize they are "behind."
/// Receptionists periodically
/// gossip their "observed sequence numbers", which is a set of `Receptionist@SequenceNr`. When a receptionist
/// notices that for a given
/// remote receptionist an observed `seqNr` is _lower_ than it has already _applied_ to its state, it performs an
/// ack/pull from that node directly.
///
/// This protocol requires that peers communicate with the "origin" receptionist of an actor to obtain its registration,
/// and therefore is NOT a full gossip implementation. The gossip is only used to detect that a pull shall be performed,
/// and the pull from thereon happens directly between those peers, which the recipient MAY flow control if it so
/// wanted to.
///
/// Discussion, Upside: This method as upsides which reflect the p2p nature of actor communication, e.g.: Since to
/// obtain a registration of an actor
/// on node `A`, we must communicate with node `A`, this means that if we CANNOT for whatever reason communicate
/// with it (e.g. unreachability),
/// even if we got the reference registration, and emitted it to users, it may end up not being useful.
///
/// Discussion, Downside: Unlike in a full peer to peer gossip replicated receptionist implementation, nodes MUST
/// communicate with the
/// origin receptionist to obtain refs from it. This can cause a "popular node" to get overwhelmed with having to
/// stream to many other
/// nodes its members... In this implementation we considered the tradeoffs and consider smaller clusters but large
/// amounts of actors
/// to be the dominant usage pattern, and thus are less worried about the large fan-out/in-cast of these ops
/// streams. This may change
/// as we face larger clusters and we'd love to explore a full CRDT based implementation that DOES NOT need to full-
/// state-sync periodically
/// (which is the reason we avoided an CRDT implementation in the first place today, as we would have to perform a
/// full-state sync of a potentially
/// _very large_ Dictionary<Key: Set<ActorRef<T>>).
///
/// 1) Members form a cluster, each has exactly one well known receptionist
/// 2) Upon joining, the new receptionist introduces itself and pulls, by sending ack(until: 0)
/// 3) All receptionists receive this and start a replay for it, from the `0`
///
/// Gossip, of Latest Op SeqNr:
/// - Receptionists gossip about their latestSequenceNr (each has a sequence Nr, associated with add/remove it performs)
/// 1) When a receptionist receives gossip, it looks at the numbers, and if it notices ANY receptionist where it is
/// "behind",
///    i.e. we know A@4, but gossip claims it is @10, then we send to it `ack(4)` which causes the receptionist to
/// reply with
///    its latest information
///  - Pushed information is batched (!), i.e the pushed would send only e.g. 50 updates, yet still inform us with its
///   latest SeqNr, and we'd notice that actually bu now it already is @100, thus we `ack(50)`, and it continues the
/// sending.
///   (Note that we simply always `ack(latest)` and if in the meantime the pusher got more updates, it'll push those
/// to us as well.
///
/// - SeeAlso: [Wikipedia: Atomic broadcast](https://en.wikipedia.org/wiki/Atomic_broadcast)
public distributed actor OpLogDistributedReceptionist: DistributedReceptionist, CustomStringConvertible {
    public typealias ActorSystem = ClusterSystem
    internal typealias ReceptionistRef = OpLogDistributedReceptionist
    internal typealias Key<Guest: DistributedActor> = DistributedReception.Key<Guest>
    where Guest.ActorSystem == ClusterSystem

    internal enum ReceptionistOp: OpLogStreamOp, Codable {
        case register(key: AnyDistributedReceptionKey, identity: ID)
        case remove(key: AnyDistributedReceptionKey, identity: ID)

        internal var isRegister: Bool {
            switch self {
            case .register:
                return true

            default:
                return false
            }
        }

        internal var isRemove: Bool {
            switch self {
            case .remove:
                return true

            default:
                return false
            }
        }

        internal var key: AnyDistributedReceptionKey {
            switch self {
            case .register(let key, _):
                return key

            case .remove(let key, _):
                return key
            }
        }
    }

    internal static var props: Props {
        var actorProps: Props = Props()
        actorProps.systemActor = true
        actorProps.wellKnown = true
        actorProps.knownActorName = ActorPath.distributedActorReceptionist.name
        return actorProps
    }

    @ActorID.Metadata(\.wellKnown)
    internal var wellKnownName: String

    internal let instrumentation: ReceptionistInstrumentation

    /// Stores the actual mappings of keys to actors.
    internal let storage: DistributedReceptionistStorage = DistributedReceptionistStorage()

    internal lazy var log: Logger = .init(actor: self)

    /// Per known receptionist replayer instances, pointing at the latest confirmed message.
    /// Resuming a replay means getting any ops that were not yet observed by the receptionist.
    ///
    /// Replays are triggered upon receiving an `AckOps`, which simultaneously act as ACKing any previously
    /// replayed messages.
    internal var peerReceptionistReplayers: [ReceptionistRef: OpLog<ReceptionistOp>.Replayer]

    /// Local operations log; Replaying events in it results in restoring the key:actor mappings known to this
    /// actor locally.
    internal let ops: OpLog<ReceptionistOp>

    internal var membership: Cluster.Membership

    internal var eventsListeningTask: Task<Void, Error>?

    // MARK: Timers

    internal var slowACKReplicationTimerTask: Task<Void, Error>?
    internal var flushTimerTasks: [Int: Task<Void, Error>] = [:]

    /// Important: This safeguards us from the following write amplification scenario:
    ///
    /// Since:
    /// - `AckOps` serves both as an ACK and "poll", and
    /// - `AckOps` is used to periodically spread information
    internal var nextPeriodicAckPermittedDeadline: [ID: ContinuousClock.Instant]

    /// Sequence numbers of operation-logs that we have observed, INCLUDING our own latest operation's seqNr.
    /// In other words, each receptionist has their own operation-log, and we observe and store the latest seqNr
    /// we have seen from them.
    internal var observedSequenceNrs: VersionVector

    /// Tracks up until what SeqNr we actually have applied the operations to our `storage`.
    ///
    /// The difference between these versions at given peer and the `maxObservedSequenceNr` at given peer,
    /// gives a good idea how far "behind" we are with regards to changed performed at that peer.
    internal var appliedSequenceNrs: VersionVector

    internal init(settings: ReceptionistSettings, system: ActorSystem) async {
        self.actorSystem = system
        self.instrumentation = system.settings.instrumentation.makeReceptionistInstrumentation()

        self.ops = OpLog(of: ReceptionistOp.self, batchSize: settings.syncBatchSize)
        self.membership = .empty
        self.peerReceptionistReplayers = [:]

        self.nextPeriodicAckPermittedDeadline = [:]

        self.observedSequenceNrs = .empty
        self.appliedSequenceNrs = .empty

        // === listen to cluster events ------------------
        self.wellKnownName = ActorPath.distributedActorReceptionist.name
        assert(
            self.id.path.description == "/system/receptionist",
            "\(Self.self) expects to be on well known path: /system/receptionist, but was: \(self.id.fullDescription)"
        )

        self.eventsListeningTask = Task { [weak self, system] in
            try await self?.whenLocal { localReceptionist in
                for try await event in system.cluster.events {
                    localReceptionist.onClusterEvent(event: event)
                }
            }
        }

        // === timers ------------------
        // periodically gossip to other receptionists with the last seqNr we've seen,
        // and if it happens to be outdated by then this will cause a push from that node.
        self.slowACKReplicationTimerTask = Task { [weak self] in
            await self?.whenLocal { myself in
                for await _ in AsyncTimerSequence.repeating(
                    every: system.settings.receptionist.ackPullReplicationIntervalSlow,
                    clock: .continuous
                ) {
                    myself.periodicAckTick()
                }
            }
        }

        self.log.debug("Initialized receptionist")
    }

    deinit {
        self.eventsListeningTask?.cancel()
        self.slowACKReplicationTimerTask?.cancel()
    }

}
