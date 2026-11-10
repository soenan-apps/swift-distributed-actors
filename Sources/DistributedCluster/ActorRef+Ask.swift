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

import Distributed
import Foundation

import class NIO.EventLoopFuture
import struct NIO.EventLoopPromise
import struct NIO.Scheduled

extension ActorRef {
    /// Sends a question carrying a one-reply actor reference and fails when its timeout expires.
    /// Annotate the returned `AskResponse<Answer>` to select the reply type.
    /// The question builder must not capture mutable actor state.
    /// Source defaults identify the caller; their values are retained for timeout diagnostics.
    internal func ask<Answer>(
        timeout: Duration,
        _ makeQuestion: (ActorRef<Answer>) -> Message,
        file: String = #filePath,
        function: String = #function,
        line: UInt = #line
    ) -> AskResponse<Answer> {
        guard let system = self.actorSystem else {
            return .completed(.failure(RemoteCallError(.clusterAlreadyShutDown)))
        }

        if system.isShuttingDown {
            return .completed(.failure(RemoteCallError(.clusterAlreadyShutDown)))
        }

        do {
            try system.serialization.ensureSerializer(Answer.self)
        } catch {
            return AskResponse.completed(.failure(error))
        }

        let promise: EventLoopPromise<Answer> = system.eventLoopGroup.next().makePromise(of: Answer.self)

        do {
            let askRef: ActorRef<Answer> = try system.spawn(  // "ask" is going away in favor of raw "remoteCalls"
                .ask,
                AskActor.behavior(
                    promise,
                    ref: self,
                    timeout: timeout,
                    source: AskSource(file: file, function: function, line: line)
                )
            )

            let message: Message = makeQuestion(askRef)
            self.tell(message, file: file, line: line)
        } catch {
            promise.fail(error)
        }

        return .nioFuture(promise.futureResult)
    }
}
