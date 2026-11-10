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

/// Protocol to be implemented by workers participating in a simple ``WorkerPool``.
public protocol DistributedWorker: DistributedActor where ActorSystem == ClusterSystem {
    /// The request payload accepted by this worker.
    associatedtype WorkItem: Codable, Sendable
    /// The result returned after the worker finishes a request.
    associatedtype WorkResult: Codable, Sendable

    /// Processes one work request and returns its result.
    distributed func submit(work: WorkItem) async throws -> WorkResult
}
#endif
