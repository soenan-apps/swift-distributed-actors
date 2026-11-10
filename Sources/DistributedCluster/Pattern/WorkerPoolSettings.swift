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

#if !canImport(Musl)
import Distributed
import Logging
import OrderedCollections

/// Used to configure a `WorkerPool`.
public struct WorkerPoolSettings<Worker: DistributedWorker> where Worker.ActorSystem == ClusterSystem {
    /// Log level at which the worker pool will log its internal messages.
    /// Usually not interesting unless debugging the workings of a worker pool and workers joining/leaving it.
    internal var logLevel: Logger.Level = .trace

    /// Configures how to select / discover actors for the pool.
    internal var selector: WorkerPool<Worker>.Selector

    /// Configures how the "next" worker is determined for submitting a work request.
    /// Generally random strategies or a form of round robin are preferred, but we
    /// could implement more sophisticated workload balancing/estimating strategies as well.
    ///
    /// Defaults to a simple round-robin strategy.
    internal var strategy: WorkerPool<Worker>.Strategy

    /// Determine what action should be taken once the number of alive workers in the pool reaches zero (after being
    /// positive for at least a moment).
    ///
    /// The default value depends on the `selector` and is:
    /// - `.crash` for the `.static` selector,
    /// - `.awaitNewWorkers` for the `.dynamic` selector, as it is assumed that replacement workers will likely be
    /// spawned
    ///    in place of terminated workers. Messages sent to the pool while no workers are available will be buffered (up
    /// to `noWorkersAvailableBufferSize` messages).
    internal var whenAllWorkersTerminated: WorkerPool<Worker>.AllWorkersTerminatedDirective

    /// Configures worker discovery and the strategy used to select the next worker.
    public init(selector: WorkerPool<Worker>.Selector, strategy: WorkerPool<Worker>.Strategy = .random) {
        self.selector = selector
        self.strategy = strategy

        switch selector.underlying {
        case .dynamic:
            self.whenAllWorkersTerminated = .awaitNewWorkers

        case .static:
            let message: String =
                "Static worker pool exhausted, all workers have terminated, selector was [\(selector)]."
            self.whenAllWorkersTerminated = .throw(
                WorkerPoolError(.staticPoolExhausted(message))
            )
        }
    }

    /// Rejects configurations that cannot supply or replace a worker.
    @discardableResult
    public func validate() throws -> Self {
        switch self.selector.underlying {
        case .static(let workers) where workers.isEmpty:
            throw WorkerPoolError(
                .emptyStaticWorkerPool("Illegal empty collection passed to `.static` worker pool!")
            )

        case .static(let workers):
            if case .awaitNewWorkers = self.whenAllWorkersTerminated {
                let message: String = """
                    WorkerPool configured as [.static(\(workers))], MUST NOT be configured to await for new workers \
                    as new workers are impossible to spawn and add to the pool in the static configuration. The pool \
                    MUST terminate when in .static mode and all workers terminate. Alternatively, use a .dynamic pool, \
                    and provide an initial set of workers.
                    """
                throw WorkerPoolError(.awaitNewWorkersForStaticPool(message))
            }

        default:
            ()  // ok
        }

        return self
    }
}
#endif
