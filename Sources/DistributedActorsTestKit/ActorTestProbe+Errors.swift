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
    /// Clear any buffered messages from the probe's queue.
    ///
    /// Blocks until no more message remains to be dropped.
    /// Note that if the probe is concurrently being sent messages as it is clearing them, this may result in
    /// spinning forever,
    /// or for in-deterministic amounts of time.
    public func clearMessages() {
        do {
            while try self.maybeExpectMessage() != nil {
                ()  // dropping messages
            }
        } catch {
            ()  // no messages in queue; i.e. nothing to clear; we're good
        }
    }
}

extension ActorTestProbe {
    @discardableResult
    private func within<T>(_ timeout: Duration, _ block: () throws -> T) throws -> T {
        let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(timeout)
        var lastObservedError: Error?
        while !deadline.isBefore(.now) {
            do {
                return try block()
            } catch {
                // keep error, try again...
                lastObservedError = error
            }
        }
        if let lastError = lastObservedError {
            throw lastError
        }
        throw ExpectationError.withinDeadlineExceeded(timeout: timeout)
    }
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Failure helpers
    /// Returns a failure with additional information of the probes last observed messages.
    /// Most useful as the `else` in an guard expression where the left hand side was an [expectMessage].
    ///
    /// Examples:
    ///
    ///     guard ... else { throw p.failure("failed to extract expected information") }
    ///     guard case let .spawned(child) = try p.expectMessage() else { throw p.failure() }
    public func error(
        _ message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Error {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        var fullMessage: String = message ?? "ActorTestProbe failure."
        switch self.lastMessage {
        case .some(let observedMessage):
            fullMessage += " Last message observed was: [\(observedMessage)]."

        case .none:
            fullMessage += " No message was observed before this failure."
        }
        return callSite.error(fullMessage)
    }
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Expecting messages with matching/extracting callbacks
    /// Expects a message and applies the nested logic to extract values out of it.
    ///
    /// The callback MAY return `nil` in order to signal "this is not the expected message", or throw an error itself.
    public func expectMessageMatching<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        _ matchExtract: (Message
    ) throws -> T?
    ) throws -> T {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let timeout: Duration = self.expectationTimeout
        do {
            let receivedMessage: Message = try self.receiveMessage(within: timeout)
            guard let extracted = try matchExtract(receivedMessage) else {
                let failureMessage: String = "Received \(Message.self) message, however it did not pass the "
                    + "matching check, "
                    + "" + "and did not produce the requested \(T.self)."
                throw callSite.error(failureMessage)
            }
            return extracted
        } catch {
            let failureMessage: String = "Did not receive matching [\(Message.self)] message within "
                + "[\(timeout.prettyDescription)], "
                + "error: \(error)"
            throw callSite.error(failureMessage)
        }
    }
}
