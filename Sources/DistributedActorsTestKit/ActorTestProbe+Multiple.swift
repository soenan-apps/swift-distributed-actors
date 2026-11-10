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
    /// Expects multiple messages to arrive at the TestProbe and returns it for further assertions.
    /// See also the `expectMessagesInAnyOrder([Message])` overload which provides automatic equality checking.
    ///
    /// - Warning: Blocks the current thread until the `expectationTimeout` is exceeded or an message is received
    /// by the actor.
    public func expectMessages(
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws -> [Message] {
        try self.expectMessages(count: count, within: self.expectationTimeout, file: file, line: line, column: column)
    }

    /// Expects multiple messages to arrive at the TestProbe and returns it for further assertions.
    /// See also the `expectMessagesInAnyOrder([Message])` overload which provides automatic equality checking.
    ///
    /// - Warning: Blocks the current thread until the `expectationTimeout` is exceeded or an message is received
    /// by the actor.
    public func expectMessages(
        count: Int,
        within timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws -> [Message] {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(timeout)
        var receivedMessages: [Message] = []
        do {
            receivedMessages.reserveCapacity(count)
            while deadline.hasTimeLeft() {
                do {
                    let message: Message = try self.receiveMessage(within: deadline.timeLeft)
                    receivedMessages.append(message)
                    self.lastMessage = message
                    if receivedMessages.count == count {
                        return receivedMessages
                    }
                } catch {
                    switch error {
                    case ExpectationError.noMessagesInQueue:
                        break

                    default:
                        throw error
                    }
                }
            }
            throw ExpectationError.notEnoughMessagesInQueue(actualCount: receivedMessages.count, expectedCount: count)
        } catch {
            let failureMessage: String =
                "Did not receive expected messages (count: \(count)) of type "
                + "[\(Message.self)] "
                + "within [\(timeout.prettyDescription)], got: \(lineByLine: receivedMessages)\nerror: \(error)"
            throw callSite.error(failureMessage)
        }
    }
}

extension ActorTestProbe where Message: Equatable {
    /// Consumes the expected messages, accepting any arrival order.
    public func expectMessagesInAnyOrder(
        _ expectedMessages: [Message],
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        try self.expectMessagesInAnyOrder(
            expectedMessages,
            within: self.expectationTimeout,
            file: file,
            line: line,
            column: column
        )
    }

    /// Consumes the expected messages, accepting any arrival order.
    public func expectMessagesInAnyOrder(
        _ expectedMessages: [Message],
        within timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        var messages: [Message] = expectedMessages
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        var received: [Message] = []
        do {
            let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(timeout)
            while !messages.isEmpty {
                let receivedMessage: Message = try self.receiveMessage(within: deadline.timeLeft)
                self.lastMessage = receivedMessage
                guard let index = messages.firstIndex(where: { $0 == receivedMessage }) else {
                    throw callSite.error("Received unexpected message [\(receivedMessage)]")
                }
                received.append(messages.remove(at: index))
            }
        } catch {
            let failureMessage: String =
                "Received only (in order) [\(received)], but did not receive expected "
                + "[\(messages)]:\(String(reflecting: Message.self)) within "
                + "[\(timeout.prettyDescription)], error: \(error)"
            throw callSite.error(failureMessage)
        }
    }
}
