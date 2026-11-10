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
    /// Expects a message to "maybe" arrive at the `ActorTestProbe` and returns it for further assertions,
    /// if no message arrives within the timeout (by default `expectationTimeout`) a `nil` value is returned.
    ///
    /// In general these the `maybeExpect` family of methods is more useful in loops or for testing optional replies,
    /// when a reply may or may not arrive (i.e. it is known to be racy).
    ///
    /// - SeeAlso: `expectMessage(file:line:column)` that throws and fails if no message is encountered during the
    /// timeout.
    ///
    /// - Warning: Blocks the current thread until the `expectationTimeout` is exceeded or a message is received
    /// by the actor.
    public func maybeExpectMessage() throws -> Message? {
        self.maybeExpectMessage(within: self.expectationTimeout)
    }

    /// Expects a message to "maybe" arrive at the `ActorTestProbe` and returns it for further assertions,
    /// if no message arrives within the timeout (by default `expectationTimeout`) a `nil` value is returned.
    ///
    /// In general these the `maybeExpect` family of methods is more useful in loops or for testing optional replies,
    /// when a reply may or may not arrive (i.e. it is known to be racy).
    ///
    /// - SeeAlso: `expectMessage(within:file:line:column)` that throws and fails if no message is encountered
    /// during the timeout.
    ///
    /// - Warning: Blocks the current thread until the `timeout` is exceeded or a message is received by the actor.
    public func maybeExpectMessage(within timeout: Duration) -> Message? {
        do {
            return try self.maybeReceiveMessage(within: timeout)
        } catch {
            return nil
        }
    }

    internal func maybeReceiveMessage(within timeout: Duration) throws -> Message? {
        let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(timeout)
        while deadline.hasTimeLeft() {
            guard let message = self.messagesQueue.poll(deadline.timeLeft) else {
                continue
            }
            self.lastMessage = message
            return message
        }
        throw ExpectationError.noMessagesInQueue
    }
}

extension ActorTestProbe where Message: Equatable {
    /// Fails in nice readable ways:
    ///
    /// - Warning: Blocks the current thread until the `expectationTimeout` is exceeded or an message is received
    /// by the actor.
    ///
    ///
    /// Example output:
    ///
    /// sact/Tests/DistributedActorsTestKitTests/ActorTestProbeTests.swift:35: error:
    /// -[DistributedActorsTestKitTests.ActorTestProbeTests
    /// test_testProbe_expectMessage_shouldFailWhenNoMessageSentWithinTimeout] : XCTAssertTrue failed -
    ///     try! probe.expectMessage("awaiting-forever")
    ///                ^~~~~~~~~~~~~~
    ///     error: Did not receive expected [awaiting-forever]:String within [1s], error: noMessagesInQueue
    ///
    /// Waits for and asserts the expected message value or prefix.
    public func expectMessage(
        _ message: Message,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        try self.expectMessage(message, within: self.expectationTimeout, file: file, line: line, column: column)
    }

    /// Waits for and asserts the expected message value or prefix.
    public func expectMessage(
        _ message: Message,
        within timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        do {
            let receivedMessage: Message = try self.receiveMessage(within: timeout)
            self.lastMessage = receivedMessage
            guard receivedMessage == message else {
                throw callSite.notEqualError(got: receivedMessage, expected: message)
            }
        } catch {
            let failureMessage: String =
                "Did not receive expected [\(message)]:\(type(of: message)) within "
                + "[\(timeout.prettyDescription)], error: \(error)"
            throw callSite.error(failureMessage)
        }
    }

    /// Waits for a message of the expected runtime type.
    public func expectMessageType<T>(
        _ type: T.Type,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        try self.expectMessageType(type, within: self.expectationTimeout, file: file, line: line, column: column)
    }

    /// Waits for a message of the expected runtime type.
    public func expectMessageType<T>(
        _ type: T.Type,
        within timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let receivedMessage: Message = try self.receiveMessage(within: timeout)
        self.lastMessage = receivedMessage
        guard receivedMessage is T else {
            throw callSite.notEqualError(got: receivedMessage, expected: type)
        }
    }
}

extension ActorTestProbe where Message: StringProtocol {
    /// Waits for and asserts the expected message value or prefix.
    public func expectMessage(
        prefix: Message,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        try self.expectMessage(prefix: prefix, within: self.expectationTimeout, file: file, line: line, column: column)
    }

    /// Waits for and asserts the expected message value or prefix.
    public func expectMessage(
        prefix: Message,
        within timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        do {
            let receivedMessage: Message = try self.receiveMessage(within: timeout)
            self.lastMessage = receivedMessage
            guard receivedMessage.starts(with: prefix) else {
                throw callSite.notMatchingPrefixError(got: receivedMessage, expected: prefix)
            }
        } catch {
            let failureMessage: String =
                "Did not receive String message with prefix [\(prefix)] within "
                + "[\(timeout.prettyDescription)], error: \(error)"
            throw callSite.error(failureMessage)
        }
    }
}
