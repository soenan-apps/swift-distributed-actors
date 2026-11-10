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

/// Actor-reference receptionist that replicates local registration operations between cluster peers.
public final class OperationLogClusterReceptionist {
    internal typealias Message = Receptionist.Message
    internal typealias ReceptionistRef = ActorRef<Message>

    internal enum ReceptionistOp: OpLogStreamOp, Codable {
        case register(key: AnyReceptionKey, id: ActorID)
        case remove(key: AnyReceptionKey, id: ActorID)

        internal var key: AnyReceptionKey {
            switch self {
            case .register(let key, _):
                return key

            case .remove(let key, _):
                return key
            }
        }
    }

    internal static let slowACKReplicationTick: TimerKey = "slow-ack-replication-tick"

    internal let instrumentation: ReceptionistInstrumentation
    /// Stores the actual mappings of keys to actors.
    internal let storage: ReceptionistStorage = ReceptionistStorage()

    /// Per known receptionist replayer instances, pointing at the latest confirmed message.
    /// Resuming a replay means getting any ops that were not yet observed by the receptionist.
    ///
    /// Replays are triggered upon receiving an `AckOps`, which simultaneously act as ACKing any previously
    /// replayed messages.
    internal var peerReceptionistReplayers: [ActorRef<Message>: OpLog<ReceptionistOp>.Replayer]

    /// Local operations log; Replaying events in it results in restoring the key:actor mappings known to this
    /// actor locally.
    internal let ops: OpLog<ReceptionistOp>

    internal var membership: Cluster.Membership

    /// Important: This safeguards us from the following write amplification scenario:
    ///
    /// Since:
    /// - `AckOps` serves both as an ACK and "poll", and
    /// - `AckOps` is used to periodically spread information
    internal var nextPeriodicAckPermittedDeadline: [ActorRef<Message>: ContinuousClock.Instant]

    /// Sequence numbers of operation-logs that we have observed, INCLUDING our own latest operation's seqNr.
    /// In other words, each receptionist has their own operation-log, and we observe and store the latest seqNr
    /// we have seen from them.
    internal var observedSequenceNrs: VersionVector

    /// Tracks up until what SeqNr we actually have applied the operations to our `storage`.
    ///
    /// The difference between these versions at given peer and the `maxObservedSequenceNr` at given peer,
    /// gives a good idea how far "behind" we are with regards to changed performed at that peer.
    internal var appliedSequenceNrs: VersionVector

    internal init(
        settings: ReceptionistSettings,
        instrumentation: ReceptionistInstrumentation = NoopReceptionistInstrumentation()
    ) {
        self.instrumentation = instrumentation

        self.ops = .init(of: ReceptionistOp.self, batchSize: settings.syncBatchSize)
        self.membership = .empty
        self.peerReceptionistReplayers = [:]

        self.observedSequenceNrs = .empty
        self.appliedSequenceNrs = .empty

        self.nextPeriodicAckPermittedDeadline = [:]
    }

}
