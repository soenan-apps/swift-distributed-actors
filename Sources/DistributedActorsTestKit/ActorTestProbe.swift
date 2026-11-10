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

/// A special actor that can be used in place of real actors, yet in addition exposes useful assertion methods
/// which make testing asynchronous actor interactions simpler.
///
/// - SeeAlso: `ActorableTestProbe` which is the equivalent API for `Actorable`s.
public final class ActorTestProbe<Message: Codable>: @unchecked Sendable {
    internal typealias ProbeCommands = ActorTestProbeCommand<Message>
    internal enum TestProbeInitializationError: Error {
        case failedToObtainUnderlyingCell
    }

    internal enum ExpectationError: Error {
        case noMessagesInQueue
        case notEnoughMessagesInQueue(actualCount: Int, expectedCount: Int)
        case timeoutAwaitingMessage(expected: AnyObject, timeout: Duration)
        case withinDeadlineExceeded(timeout: Duration)
    }

    /// Naming strategy for anonymous test probes.
    /// By default test probes are named as `$testProbe-###`.
    public static var naming: ActorNaming {
        // has to be computed property since: static stored properties are not supported in generic types
        ActorNaming(unchecked: .prefixed(prefix: "$testProbe", suffixScheme: .sequentialNumeric))
    }

    /// Name of the test probe (and underlying actor).
    public let name: String
    internal let internalRef: ActorRef<ProbeCommands>
    internal let exposedRef: ActorRef<Message>
    internal let distributedProbe: TestProbeInternal
    internal let settings: ActorTestKitSettings
    /// Blocking linked queue, available to run assertions on
    internal let messagesQueue: LinkedBlockingQueue<Message> = LinkedBlockingQueue<Message>()
    /// Blocking linked queue, available to run assertions on
    internal let signalQueue: LinkedBlockingQueue<SystemMessages> = LinkedBlockingQueue<SystemMessages>()
    /// Blocking linked queue, specialized for keeping only termination signals (so that we can assert
    /// terminations, independently of other signals)
    internal let terminationsQueue: LinkedBlockingQueue<Signals.Terminated> = LinkedBlockingQueue<Signals.Terminated>()
    /// Last message received (by using an `expect...` call), by this probe.
    public var lastMessage: Message?
    /// The reference to the underlying "mock" actor.
    /// Sending messages to this reference allows the probe to inspect them using the `expect...` family of functions.
    public var ref: ActorRef<Message> {
        self.exposedRef
    }

    internal var expectationTimeout: Duration {
        self.settings.expectationTimeout
    }

    /// Prepares and spawns a new test probe. Users should use `testKit.makeTestProbe(...)` instead.
    internal init(
        _ makeRef: (Behavior<ProbeCommands>) throws -> ActorRef<ProbeCommands>,
        settings: ActorTestKitSettings,
        system: ClusterSystem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        self.settings = settings
        let behavior: Behavior<ProbeCommands> = Self.behavior(
            messageQueue: self.messagesQueue,
            terminationsQueue: self.terminationsQueue
        )
        do {
            self.internalRef = try makeRef(behavior)
        } catch {
            let _: Never = fatalErrorBacktrace(
                "Failed to make actor ref for \(ActorTestProbe<Message>.self): "
                    + "[\(error)]:\(String(reflecting: type(of: error)))",
                file: file,
                line: line
            )
        }
        self.name = self.internalRef.id.name
        let wrapRealMessages: (Message) -> ProbeCommands = { msg in
            ProbeCommands.realMessage(message: msg)
        }
        guard let cell = self.internalRef.unsafeUnwrapCell.actor else {
            preconditionFailure("The probe reference must have a local actor cell")
        }
        self.exposedRef = cell.messageAdapter(wrapRealMessages)
        self.distributedProbe = TestProbeInternal(actorSystem: system)
    }

    private static func behavior(
        messageQueue: LinkedBlockingQueue<Message>,
        terminationsQueue: LinkedBlockingQueue<Signals.Terminated>
    ) -> Behavior<ProbeCommands> {
        Behavior<ProbeCommands>.receive { context, message in
            guard let cell = context.myself.unsafeUnwrapCell.actor else {
                throw TestProbeInitializationError.failedToObtainUnderlyingCell
            }
            switch message {
            case .realMessage(let msg):
                traceLog_Probe("Probe received: [\(msg)]:\(type(of: msg))", file: #fileID, line: #line)
                // real messages are stored directly
                messageQueue.enqueue(msg)
                return .same

            // probe commands:
            case let .watchCommand(who, file, line):
                cell.deathWatch.watch(
                    watchee: who,
                    with: nil,
                    myself: context.downcastUnsafe,
                    file: file,
                    line: line
                )
                return .same

            case .unwatchCommand(let who):
                cell.deathWatch.unwatch(watchee: who, myself: context.myself)
                return .same

            case .forwardCommand(let send):
                send()
                return .same

            case .stopCommand:
                return .stop
            }
        }.receiveSignal { _, signal in
            traceLog_Probe("Probe received: [\(signal)]:\(type(of: signal))", file: #fileID, line: #line)
            switch signal {
            case let terminated as Signals.Terminated:
                terminationsQueue.enqueue(terminated)
                return .same

            default:
                return .unhandled
            }
        }
    }
}
