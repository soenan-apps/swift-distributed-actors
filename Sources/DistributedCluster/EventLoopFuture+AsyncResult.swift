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

import NIO

extension EventLoopFuture: AsyncResult {
    internal func onComplete(_ callback: @escaping (Result<Value, Error>) -> Void) {
        self.whenComplete(callback)
    }

    internal func withTimeout(after timeout: Duration) -> EventLoopFuture<Value> {
        if timeout == .effectivelyInfinite {
            return self
        }

        let promise: EventLoopPromise<Value> = self.eventLoop.makePromise()
        let timeoutTask: Scheduled<Void> = self.eventLoop.scheduleTask(in: timeout.toNIO) {
            promise.fail(
                TimeoutError(
                    message: "\(type(of: self)) timed out after \(timeout.prettyDescription)", timeout: timeout
                )
            )
        }
        self.whenComplete { result in
            timeoutTask.cancel()
            promise.completeWith(result)
        }

        return promise.futureResult
    }
}
