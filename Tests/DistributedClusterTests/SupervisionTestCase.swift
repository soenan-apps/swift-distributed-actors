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

import DistributedActorsTestKit
import Foundation
import NIO
import XCTest

@testable import DistributedCluster

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

internal class SupervisionTestCase: SingleClusterSystemXCTestCase {
    internal enum FaultyError: Error, NotActuallyCodableMessage {
        case boom(
            message:
                String
        )
    }

    internal enum FaultyMessage: NotActuallyCodableMessage {
        case pleaseThrow(
            error:
                Error
        )
        case echo(
            message: String,
            replyTo:
                ActorRef<WorkerMessages>
        )
        case pleaseFailAwaiting(
            message:
                String
        )
    }

    internal enum SimpleProbeMessages: Equatable, NotActuallyCodableMessage {
        case spawned(
            child:
                ActorRef<FaultyMessage>
        )
        case echoing(
            message:
                String
        )
    }

    internal enum WorkerMessages: Equatable, NotActuallyCodableMessage {
        case setupRunning(
            ref:
                ActorRef<FaultyMessage>
        )
        case echo(
            message:
                String
        )
    }

    internal enum FailureMode: NotActuallyCodableMessage {
        case throwing

        internal func fail() throws {
            switch self {
            case .throwing:
                throw FaultyError.boom(
                    message:
                        "SIGNAL_BOOM"
                )
            }
        }
    }

    internal struct PleaseReplyError: Error, Codable, Equatable {}
    internal struct EasilyCatchableError: Error, Equatable {}
    internal struct CantTouchThisError: Error, Equatable {}
    internal struct CatchMeError: Error, Equatable {}

    internal func faulty(probe: ActorRef<WorkerMessages>?) -> Behavior<FaultyMessage> {
        .setup { context in
            probe?.tell(.setupRunning(ref: context.myself))

            return .receiveMessage { message in
                switch message {
                case .pleaseThrow(let error):
                    throw error

                case let .echo(msg, sender):
                    sender.tell(.echo(message: "echo:\(msg)"))
                    return .same

                case .pleaseFailAwaiting(let msg):
                    let failed: EventLoopFuture<String> = context.system.eventLoopGroup.next().makeFailedFuture(
                        Boom("Failed: \(msg)")
                    )
                    return context.awaitResultThrowing(of: failed, timeout: .seconds(1)) { _ in
                        .same
                    }
                }
            }
        }
    }
}
