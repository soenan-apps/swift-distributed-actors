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
import DistributedActorsConcurrencyHelpers
import Foundation
import XCTest

@testable import DistributedCluster

extension ActorTestProbe {
    /// Instructs this probe to watch the passed in actor.
    /// The `watchee` actor is from now on being watched and we will be notified when it terminates.
    ///
    /// There is no difference between keeping the passed in reference or using the returned ref from this method.
    /// The actor is the being watched subject, not a specific reference to it.
    ///
    /// This enables it to use `expectTerminated` to await for the watched actors termination.
    ///
    /// - Returns: reference to the passed in `watchee` actor.
    /// - SeeAlso: `DeathWatch`
    @discardableResult
    public func watch<Act>(
        _ watchee: Act,
        file: String = #filePath,
        line: UInt = #line
    ) async -> Act
    where
        Act: DistributedActor,
        Act.ActorSystem == ClusterSystem
    {
        _ = await self.distributedProbe.whenLocal { localProbe in
            localProbe.watchTermination(of: watchee, file: file, line: line)
        }
        return watchee
    }

    /// Suspends waiting for the actor to become terminated.
    ///
    /// - Warning: Remember to first `watch` the actor you are expecting termination for,
    ///            otherwise the termination signal will never be received.
    ///
    /// - SeeAlso: `DeathWatch`
    public func expectTermination(
        of actor: ActorID,
        within timeout: Duration? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async throws {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let effectiveTimeout: Duration = timeout ?? self.expectationTimeout
        let task: Task<Void, Error> = Task<Void, Error>.cancelAfter(
            timeout: effectiveTimeout,
            timeoutError: callSite.error(
                "Expected [\(actor)] to terminate within "
                    + "\(effectiveTimeout.prettyDescription)"
            )
        ) {
            _ = try await self.distributedProbe.whenLocal { localProbe in
                for await terminated in localProbe.terminatedQueue.items {
                    guard terminated == actor else {
                        throw callSite.error(
                            "Expected [\(actor)] to terminate, but received [\(terminated)] "
                                + "terminated "
                                + "signal first instead. " + "This could be an ordering issue, inspect "
                                + "your signal order assumptions."
                        )
                    }
                    // Only expecting one, so we are done
                    break
                }
            }
        }
        return try await task.value
    }
}
