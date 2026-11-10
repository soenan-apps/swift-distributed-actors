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
    internal var behavior: Behavior<Message> {
        .setup { context in
            self.makeBehavior(context: context)
        }
    }

    internal func makeBehavior(context: ActorContext<Message>) -> Behavior<Message> {
        context.log.debug("Initialized receptionist")
        let onClusterEventRef: ActorRef<Cluster.Event> = context.subReceive(Cluster.Event.self) { event in
            self.onClusterEvent(context, event: event)
        }
        context.system.cluster.events.subscribe(onClusterEventRef)
        context.timers.startPeriodic(
            key: Self.slowACKReplicationTick,
            message: Self.PeriodicAckTick(),
            interval: context.system.settings.receptionist.ackPullReplicationIntervalSlow
        )
        return Behavior<Receptionist.Message>.receiveMessage { message in
            self.receive(context: context, message: message)
        }.receiveSpecificSignal(Signals.Terminated.self) { _, terminated in
            self.onTerminated(context: context, terminated: terminated)
            return .same
        }
    }

    internal func receive(context: ActorContext<Message>, message: Message) -> Behavior<Message> {
        self.tracelog(context, .receive, message: message)
        switch message {
        case let push as PushOps:
            self.receiveOps(context, push: push)

        case let ack as AckOps:
            self.receiveAckOps(context, until: ack.until, by: ack.peer)

        case _ as PeriodicAckTick:
            self.onPeriodicAckTick(context)

        case let registration as AnyReceptionRegistration:
            self.onRegister(context: context, message: registration)

        case let lookup as ReceptionLookup:
            self.onLookup(context: context, message: lookup)

        case let subscription as ReceptionSubscription:
            self.onSubscribe(context: context, message: subscription)

        case let tick as ReceptionistListingFlushTick:
            self.onDelayedListingFlushTick(context: context, message: tick)

        default:
            context.log.warning("Received unexpected message: \(String(reflecting: message)), \(type(of: message))")
        }
        return .same
    }
}
