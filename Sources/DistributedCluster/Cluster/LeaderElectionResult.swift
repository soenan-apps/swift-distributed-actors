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

import Logging
import NIO

/// Result of running a `LeaderElection`, which may be performed asynchronously (or not).
///
/// Synchronous leader elections are usually implemented by predictably ordering the nodes, e.g. ordering them by
/// address
/// and picking the "lowest", which is a variant of "ranking" leader election. Asynchronous elections may involve having
/// to reach out to the other members and them performing a "vote" about who shall become the leader. As this involves
/// actor coordination, the result of such election is going to be provided asynchronously.
///
/// A change in leadership will result in a `Cluster.LeadershipChange` event being emitted in the system's cluster event
/// stream.
public struct LeaderElectionResult: AsyncResult {
    public typealias Value = Cluster.LeadershipChange?

    internal let future: EventLoopFuture<Cluster.LeadershipChange?>

    internal init(_ future: EventLoopFuture<Cluster.LeadershipChange?>) {
        self.future = future
    }

    public func onComplete(_ callback: @escaping (Result<Cluster.LeadershipChange?, Error>) -> Void) {
        self.future.whenComplete(callback)
    }

    public func withTimeout(after timeout: Duration) -> Self {
        Self(self.future.withTimeout(after: timeout))
    }
}
