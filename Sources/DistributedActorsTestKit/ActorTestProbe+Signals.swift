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
    /// Asserts that no message is received by the probe during the specified timeout.
    /// Useful for making sure that after some "terminal" message no other messages are sent.
    ///
    /// Warning: The method will block the current thread for the specified timeout.
    public func expectNoMessage(
        for timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        if let message = self.messagesQueue.poll(timeout) {
            let failureMessage: String = "Received unexpected message [\(message)]:\(type(of: message)). Did "
                + "not expect "
                + "to receive any messages for [\(timeout.prettyDescription)]."
            throw callSite.error(failureMessage)
        }
    }

    /// Asserts that no termination signals (specifically) are received by the probe during the specified timeout.
    ///
    /// Warning: The method will block the current thread for the specified timeout.
    public func expectNoTerminationSignal(
        for timeout: Duration,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        if let termination = self.terminationsQueue.poll(timeout) {
            let failureMessage: String = "Received unexpected termination [\(termination)]. Did not expect to receive "
                + "any termination for [\(timeout.prettyDescription)]."
            throw callSite.error(failureMessage)
        }
    }
}
// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Expecting signals
extension ActorTestProbe {
    /// Expects a signal to be enqueued to this actor within the default `expectationTimeout`.
    public func expectSignal(
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws -> SystemMessages {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let maybeGot: SystemMessages? = self.signalQueue.poll(self.expectationTimeout)
        guard let got = maybeGot else {
            throw callSite.error("Expected Signal however no signal arrived within "
                + "\(self.expectationTimeout.prettyDescription)")
        }
        return got
    }

    /// Expects the `expected` system message
    public func expectSignal(
        expected: SystemMessages,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let got: SystemMessages = try self.expectSignal(file: file, line: line, column: column)
        if got != expected {
            throw callSite.notEqualError(got: got, expected: expected)
        }
    }
}

extension ActorTestProbe {
    /// Instructs this probe to watch the passed in actor.
    /// The `watchee` actor is from now on being watched and we will receive `.terminated` signals about it.
    ///
    /// There is no difference between keeping the passed in reference or using the returned ref from this method.
    /// The actor is the being watched subject, not a specific reference to it.
    ///
    /// This enables it to use `expectTerminated` to await for the watched actors termination.
    ///
    /// - Returns: reference to the passed in `watchee` actor.
    /// - SeeAlso: `DeathWatch`
    @discardableResult
    public func watch<M>(_ watchee: ActorRef<M>, file: String = #filePath, line: UInt = #line) -> ActorRef<M> {
        self.internalRef.tell(ProbeCommands.watchCommand(who: watchee.asAddressable, file: file, line: line))
        return watchee
    }

    /// Instructs the probe to send a message on our behalf, this is useful to enforce ordering e.g. when the
    /// probe has to perform a watch,
    /// followed by a message send and we want to ensure that the watch has been processed -- we can do so by
    /// forwarding a message through
    /// the probe, which ensures ordering between the watch being sent and the message sent just now.
    ///
    /// Without this it may happen that we asked the probe to watch an actor, and send a message to the actor directly,
    /// and our direct message arrives first, before the watch at the destination, causing potentially confusing
    /// behavior
    /// in some very ordering delicate testing scenarios.
    public func forward<M>(_ message: M, to target: ActorRef<M>, file: String = #filePath, line: UInt = #line)
    where M: Codable {
        self.internalRef.tell(ProbeCommands.forwardCommand { () in target.tell(message, file: file, line: line) })
    }

    /// Instructs this probe to unwatch the passed in reference.
    ///
    /// Note that unwatch MIGHT when used with testProbes since the probe may have already stored
    /// the `.terminated` signal in its signal assertion queue, which is not modified upon `unwatching`.
    /// If you want to avoid such race, you can implement your own small actor which performs the watching
    /// and forwards signals appropriately to a probe to trigger the assertions in the tests main thread.
    ///
    /// - Returns: reference to the passed in watchee actor.
    /// - SeeAlso: `DeathWatch`
    @discardableResult
    public func unwatch<M>(_ watchee: ActorRef<M>) -> ActorRef<M> {
        self.internalRef.tell(ProbeCommands.unwatchCommand(who: watchee.asAddressable))
        return watchee
    }

    /// Returns the `Signals.Terminated` signal since one may want to perform additional assertions on the
    /// termination reason.
    ///
    /// - Warning: Remember to first `watch` the actor you are expecting termination for,
    ///            otherwise the termination signal will never be received.
    /// - Returns: the matched `.terminated` message
    /// - SeeAlso: `DeathWatch`
    @discardableResult
    public func expectTerminated<T>(
        _ ref: ActorRef<T>,
        within timeout: Duration? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws -> Signals.Terminated {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        let effectiveTimeout: Duration = timeout ?? self.expectationTimeout
        guard let terminated = self.terminationsQueue.poll(effectiveTimeout) else {
            throw callSite.error("Expected [\(ref.id)] to terminate within \(effectiveTimeout.prettyDescription)")
        }
        guard terminated.id == ref.id else {
            throw callSite.error("Expected [\(ref.id)] to terminate, but received [\(terminated.id)] terminated "
                + "signal first instead. " + "This could be an ordering issue, inspect your signal order assumptions.")
        }
        return terminated  // ok!
    }

    /// Awaits termination of all passed in actors in any order within the default `expectationTimeout`.
    ///
    /// - ***Warning**: Remember to first `watch` the actors you are expecting termination for,
    ///                 otherwise the termination signal will never be received.
    /// - SeeAlso: `DeathWatch`
    public func expectTerminatedInAnyOrder(
        _ refs: [AddressableActorRef],
        file: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let callSite: CallSiteInfo = CallSiteInfo(file: file, line: line, column: column, function: #function)
        var pathSet: Set<ActorID> = Set(refs.map(\.id))
        let deadline: ContinuousClock.Instant = ContinuousClock.Instant.fromNow(self.expectationTimeout)
        while !pathSet.isEmpty, deadline.hasTimeLeft() {
            guard let terminated = self.terminationsQueue.poll(deadline.timeLeft) else {
                throw callSite.error("Expected [\(refs)] to terminate within "
                    + "\(self.expectationTimeout.prettyDescription)")
            }
            guard pathSet.remove(terminated.id) != nil else {
                throw callSite.error("Expected any of \(pathSet) to terminate, but received [\(terminated.id)] "
                    + "terminated signal first instead. " + "This could be an ordering "
                        + "issue, inspect your signal order assumptions.")
            }
        }
    }
}
// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Test probe Lifecycle control
extension ActorTestProbe {
    /// Stops the test probe, asynchronously.
    ///
    /// - **Warning**: Since this action is asynchronous, in order to be certain that a probe has terminated
    /// before performing another task,
    ///              you may need to watch and expect it to terminate before moving on.
    public func stop() {
        // we send the stop command as normal message in order to not "overtake" other commands that were sent to it
        // not strictly required, but can yield more predictable results when used from tests after all
        self.internalRef.tell(.stopCommand)
    }
}
