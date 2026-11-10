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
    /// Determines whether fishing collects a value and whether it continues.
    public enum FishingDirective<CaughtMessage> {
        /// Collects this value and finishes fishing.
        case catchComplete(CaughtMessage)
        /// Collects this value and continues fishing.
        case catchContinue(CaughtMessage)
        /// Finishes without collecting this value.
        case complete
        /// Ignores this value and continues fishing.
        case ignore
    }

    public enum MessageFishingError: Error {
        case noMessagesCaught
    }

    /// Determines whether message fishing collects or ignores the current message.
    public enum MessageFishingDirective {
        /// Collects this value and finishes fishing.
        case catchComplete
        /// Collects this value and continues fishing.
        case catchContinue
        /// Finishes without collecting this value.
        case complete
        /// Ignores this value and continues fishing.
        case ignore
    }

    /// Expects a message to arrive at the TestProbe and returns it for further assertions.
    /// See also the `expectMessage(_:Message)` overload which provides automatic equality checking.
    ///
    /// - SeeAlso: `maybeExpectMessage(file:line:column:)` which does not fail upon encountering no message within
    /// the timeout.
    ///
    /// - Warning: Blocks the current thread until the `expectationTimeout` is exceeded or a message is received
    /// by the actor.
    public func expectMessage(
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws -> Message {
        try self.expectMessage(within: self.expectationTimeout, file: file, line: line, column: column)
    }

    /// Expects a message to arrive at the TestProbe and returns it for further assertions.
    /// See also the `expectMessage(_:Message)` overload which provides automatic equality checking.
    /// - SeeAlso: `maybeExpectMessage(within:file:line:column:)` which does not fail upon encountering no message
    /// within the timeout.
    ///
    /// - Warning: Blocks the current thread until the `timeout` is exceeded or a message is received by the actor.
    public func expectMessage(
        within timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws -> Message {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        do {
            return try self.receiveMessage(within: timeout)
        } catch {
            let failureMessage: String =
                "Did not receive message of type [\(Message.self)] within "
                + "[\(timeout.prettyDescription)], "
                + "error: \(error)"
            throw callSite.error(failureMessage)
        }
    }

    internal func receiveMessage(within timeout: Duration) throws -> Message {
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

    /// Allows for "fishing out" certain messages from the stream of incoming messages to this probe.
    /// Messages can be caught or ignored using the passed in function.
    ///
    /// Allows transforming the caught messages to `CaughtMessage` (e.g. extracting a specific payload from all
    /// incoming messages).
    /// If you need to aggregate the exact `Message` types, you prefer using `fishForMessages`.
    ///
    /// Once `MessageFishingDirective.catchComplete` or `MessageFishingDirective.complete` is returned,
    /// the function returns all so-far accumulated messages.
    public func fishFor<CaughtMessage>(
        _ type: CaughtMessage.Type,
        within timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        _ fisher: (Message) throws -> FishingDirective<CaughtMessage>
    ) throws -> [CaughtMessage] {
        let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(timeout)
        var caughtMessages: [CaughtMessage] = []
        while deadline.hasTimeLeft() {
            if let message = self.maybeExpectMessage(within: deadline.timeLeft) {
                switch try fisher(message) {
                case .catchContinue(let caught):
                    caughtMessages.append(caught)

                case .catchComplete(let caught):
                    caughtMessages.append(caught)
                    return caughtMessages

                case .ignore:
                    ()

                case .complete:
                    return caughtMessages
                }
            }
        }
        if caughtMessages.isEmpty {
            throw self.error(
                "No messages \(String(reflecting: type)) caught within "
                    + "\(timeout.prettyDescription)!",
                file: file,
                line: line,
                column: column
            )
        }
        return caughtMessages
    }

    /// Allows for "fishing out" certain messages from the stream of incoming messages to this probe.
    /// Messages can be caught or ignored using the passed in function.
    ///
    /// Accumulated messages can be transformed to a caught payload type.
    /// If you need to aggregate the exact `Message` types, you prefer using `fishForMessages`.
    ///
    /// Once `MessageFishingDirective.catchComplete` or `MessageFishingDirective.complete` is returned,
    /// the function returns all so-far accumulated messages.
    public func fishForMessages(
        within timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        _ fisher: (Message) throws -> MessageFishingDirective
    ) throws -> [Message] {
        try self.fishFor(Message.self, within: timeout, file: file, line: line, column: column) { message in
            switch try fisher(message) {
            case .catchContinue:
                return .catchContinue(message)

            case .catchComplete:
                return .catchComplete(message)

            case .ignore:
                return .ignore

            case .complete:
                return .complete
            }
        }
    }
}
