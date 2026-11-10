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

import Foundation
import NIO

/// Receives the first response to an `ActorRef.ask` request or completes it with a timeout.
/// Will either complete the `AskResponse` with the first message received, or fail
/// it with a `TimeoutError` is no response is received within the specified timeout.
///
internal enum AskActor {
    internal enum Event: NotActuallyCodableMessage {
        case timeout
    }

    internal static func behavior<Message, ResponseType>(
        _ completable: EventLoopPromise<ResponseType>,
        ref: ActorRef<Message>,
        timeout: Duration,
        source: AskSource
    ) -> Behavior<ResponseType> {
        // could we optimize the case when the target is _local_ and _terminated_ so we don't have to do the watch dance
        // (heavy if we did it always),
        // but make dead letters tell us back that our ask will never reply?
        .setup { context in
            var scheduledTimeout: Scheduled<Void>?
            if !timeout.isEffectivelyInfinite {
                let timeoutSub: ActorRef<Event> = context.subReceive(Event.self) { event in
                    switch event {
                    case .timeout:
                        let errorMessage: String = """
                            No response received for ask to [\(ref.id)] within timeout [\(timeout.prettyDescription)]. \
                            Ask was initiated from function [\(source.function)] \
                            in [\(source.file):\(source.line)] and \
                            expected response of type [\(String(reflecting: ResponseType.self))].
                            """
                        completable.fail(
                            RemoteCallError(
                                .timedOut(UUID(), TimeoutError(message: errorMessage, timeout: timeout))
                            )
                        )

                        // Hack to stop from subReceive. Should we allow this somehow?
                        //        Maybe add a SubReceiveContext or similar?
                        try context.downcastUnsafe.becomeNext(behavior: .stop)
                    }
                }

                scheduledTimeout = context.system.eventLoopGroup.next().scheduleTask(in: timeout.toNIO) {
                    timeoutSub.tell(.timeout)
                }
            }

            return .receiveMessage { message in
                scheduledTimeout?.cancel()
                completable.succeed(message)

                return .stop
            }
        }
    }
}
