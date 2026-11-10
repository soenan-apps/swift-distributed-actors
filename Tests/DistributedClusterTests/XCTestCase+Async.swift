// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed
import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

extension XCTestCase {
    // remove once XCTest supports async functions on Linux
    internal func runAsyncAndBlock(
        @_inheritActorContext @_implicitSelfCapture operation: __owned @Sendable @escaping () async throws -> Void,
        timeout: Duration = .seconds(60)
    ) throws {
        let finished: XCTestExpectation = expectation(description: "finished")
        let receptacle: BlockingReceptacle<Error?> = BlockingReceptacle<Error?>()

        let testTask: Task<Void, Never> = Task.detached {
            do {
                try await operation()
                receptacle.offerOnce(nil)
                finished.fulfill()
            } catch {
                receptacle.offerOnce(error)
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: TimeInterval(timeout.seconds))
        testTask.cancel()

        guard let error = receptacle.wait() else {
            return
        }

        if let callSiteError = error as? CallSiteError {
            XCTFail(callSiteError.explained, file: callSiteError.callSite.file, line: callSiteError.callSite.line)
        }
        throw error
    }

    internal func runAsyncAndBlock(
        @_inheritActorContext @_implicitSelfCapture operation: __owned @Sendable @escaping () async -> Void,
        timeout: Duration = .seconds(60)
    ) {
        let finished: XCTestExpectation = expectation(description: "finished")

        let testTask: Task<Void, Never> = Task.detached {
            await operation()
            finished.fulfill()
        }

        wait(for: [finished], timeout: TimeInterval(timeout.seconds))
        testTask.cancel()
    }
}
