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

extension EventLoop {
    /// Traverses elements sequentially, waiting for each future before starting the next.

    /// will cause the processing to end and the returned future will be failed.
    internal func traverseIgnore<T>(
        over elements: [T],
        _ closure: @escaping (T) -> EventLoopFuture<Void>
    ) -> EventLoopFuture<Void> {
        guard let first = elements.first else {
            return self.makeSucceededFuture(())
        }

        var acc: EventLoopFuture<Void> = closure(first)

        for element in elements.dropFirst() {
            acc = acc.flatMap { _ in
                closure(element)
            }
        }

        return acc
    }
}
