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

import DistributedActorsConcurrencyHelpers
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

extension ActorTestKit {
    /// Retries the block until it produces a value or the requested time limit expires.
    /// in which case an `EventuallyError` is thrown, along with the last encountered error thrown by block.
    ///
    /// `eventually` is designed to be used with the `expectX` functions on `ActorTestProbe`.
    ///
    /// **CAUTION**: Using `shouldX` matchers in an `eventually` block will fail the test on the first failure.
    ///
    @discardableResult
    public func eventually<T>(
        within duration: Duration,
        interval: Duration = .milliseconds(100),
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        _ block: () throws -> T
    ) throws -> T {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(duration)

        var lastError: Error?
        var polledTimes: Int = 0

        let res: T? = Self.withRepeatableContext {
            while deadline.hasTimeLeft() {
                do {
                    polledTimes += 1
                    return try block()
                } catch {
                    lastError = error
                    usleep(useconds_t(interval.microseconds))
                }
            }
            return nil
        }

        if let res {
            return res
        }

        let error: EventuallyError = EventuallyError(callSite, duration, polledTimes, lastError: lastError)
        if !Self.isInRepeatableContext() {
            XCTFail("\(error)", file: callSite.file, line: callSite.line)
        }
        throw error
    }

    /// Retries the block until it produces a value or the requested time limit expires.
    /// in which case an `EventuallyError` is thrown, along with the last encountered error thrown by block.
    ///
    /// `eventually` is designed to be used with the `expectX` functions on `ActorTestProbe`.
    ///
    /// **CAUTION**: Using `shouldX` matchers in an `eventually` block will fail the test on the first failure.
    ///
    @discardableResult
    public func eventually<T>(
        within duration: Duration,
        interval: Duration = .milliseconds(100),
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        _ block: () async throws -> T
    ) async throws -> T {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(duration)

        var lastError: Error?
        var polledTimes: Int = 0

        let res: T? = await Self.withRepeatableContext {
            while deadline.hasTimeLeft() {
                do {
                    polledTimes += 1
                    return try await block()
                } catch {
                    lastError = error
                    usleep(useconds_t(interval.microseconds))
                }
            }
            return nil
        }

        if let res {
            return res
        }

        let error: EventuallyError = EventuallyError(callSite, duration, polledTimes, lastError: lastError)
        if !Self.isInRepeatableContext() {
            XCTFail("\(error)", file: callSite.file, line: callSite.line)
        }
        throw error
    }

    /// Executes passed in block numerous times, to check the assertion holds over time.
    /// Throws an error when the block fails within the specified time amount.
    public func assertHolds(
        for duration: Duration,
        interval: Duration = .milliseconds(100),
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        _ block: () throws -> Void
    ) throws {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(duration)

        var polledTimes: Int = 0

        while deadline.hasTimeLeft() {
            do {
                polledTimes += 1
                try block()
                usleep(useconds_t(interval.microseconds))
            } catch {
                let assertionError: Error = callSite.error(
                    """
                    Failed within \(duration.prettyDescription) for block at \(file):\(line). \
                    Queried \(polledTimes) times, within \(duration.prettyDescription). \
                    Error: \(error)
                    """
                )
                XCTFail("\(assertionError)", file: callSite.file, line: callSite.line)
                throw assertionError
            }
        }
    }

    /// Checks that traversal finds exactly one actor occupying the path.
    public func assertActorPathOccupied(
        _ path: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        precondition(!path.contains("#"), "assertion path MUST NOT contain # id section of an unique path.")

        let callSiteInfo: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let res: TraversalResult<AddressableActorRef> = self.system.traverseAll { _, ref in
            if ref.id.path.description == path {
                return .accumulateSingle(ref)
            }
            return .continue
        }

        switch res {
        case .result:
            return

        case .results(let refs):
            throw callSiteInfo.error("Found more than a single ref for assertion! Got \(refs).")

        case .completed:
            throw callSiteInfo.error("Failed to find actor occupying [\(path)]!")

        case .failed(let err):
            throw callSiteInfo.error("Path \(path) was not occupied by any actor! Error: \(err)")
        }
    }

    /// Retries actor resolution until it returns a reference that is not dead.
    /// If unable to resolve a not-dead reference, this function throws, rather than returning the dead reference.
    ///
    /// This is useful when the resolution might be racing against the startup of the actor we are trying to resolve.
    public func eventuallyResolve<Message>(
        id: ActorID,
        of _: Message.Type = Message.self,
        within _: Duration = .seconds(5)
    ) throws -> ActorRef<Message> {
        let context: ResolveContext<Message> = ResolveContext<Message>(id: id, system: self.system)

        return try self.eventually(within: .seconds(3)) {
            let resolved: ActorRef<Message> = self.system.resolve(context: context)

            if resolved.id.starts(with: .dead) {
                throw self.error("Attempting to resolve not-dead [\(id)] yet resolved: \(resolved)")
            }
            return resolved
        }
    }
}
