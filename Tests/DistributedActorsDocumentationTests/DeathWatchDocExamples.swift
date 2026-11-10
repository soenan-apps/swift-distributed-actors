// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

// tag::imports[]

import DistributedCluster

// end::imports[]

internal enum Player {
    internal typealias Command = String
}

internal enum GameUnit {
    internal enum Command: Codable {
        case otherCommand
        case player(ActorRef<Player.Command>)
    }
}

internal enum GameMatch {
    internal enum Command: Codable {
        case disconnectedPleaseStop
        case playerConnected(ActorRef<Player.Command>)
    }
}

internal class DeathWatchDocExamples {
    internal func unitReady() -> Behavior<GameUnit.Command> {
        .ignore
    }

    internal func simple_watch() {
        // tag::simple_death_watch[]
        func gameUnit(player: ActorRef<Player.Command>) -> Behavior<GameUnit.Command> {
            .setup { context in
                context.watch(player)  // <1>

                return .receiveMessage { _ in  // <2>
                    // perform some game logic...
                    .same
                }  // <3>
            }
        }
        // end::simple_death_watch[]
    }

    internal func schedule_event(isPlayer: @escaping @Sendable (Signals.Terminated) -> Bool) {
        // tag::handling_termination_deathwatch[]
        let concedeTimer: TimerKey = "concede-timer"

        _ = Behavior<GameMatch.Command>.receive { context, command in
            switch command {
            case .playerConnected(let player):
                context.timers.cancel(for: concedeTimer)
                context.watch(player)
                return .same

            case .disconnectedPleaseStop:
                context.log.info("Stopping since player remained not connected for a while...")
                return .stop
            }
        }.receiveSpecificSignal(Signals.Terminated.self) { context, terminated in
            guard isPlayer(terminated) else {
                return .unhandled
            }

            context.timers.startSingle(key: concedeTimer, message: .disconnectedPleaseStop, delay: .seconds(1))
            return .same
        }
        // end::handling_termination_deathwatch[]
    }
}
