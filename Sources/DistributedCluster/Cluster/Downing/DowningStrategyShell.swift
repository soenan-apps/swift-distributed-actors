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
import Logging

internal distributed actor DowningStrategyShell {
    internal typealias ActorSystem = ClusterSystem

    internal static let path: ActorPath =
        // swiftlint:disable:next force_try
        try! ActorPath.systemRoot.appending(segment: ActorPathSegment("downingStrategy"))

    internal static var props: Props {
        var properties: Props = Props()
        properties.knownActorName = Self.path.name
        properties.systemActor = true
        properties.wellKnown = true
        return properties
    }

    internal let strategy: DowningStrategy

    private lazy var log: Logger = Logger(actor: self)

    /// `Task` for subscribing to cluster events.
    private var eventsListeningTask: Task<Void, Error>?
    /// Timer `Task`s
    private var memberTimerTasks: [Cluster.Member: Task<Void, Error>] = [:]

    internal var metadata: Logger.Metadata {
        [
            "tag": "downing",
            "downing/strategy": "\(type(of: self.strategy))",
        ]
    }

    internal init(_ strategy: DowningStrategy, system: ActorSystem) async {
        self.strategy = strategy
        self.actorSystem = system
        self.eventsListeningTask = Task { [weak self] in
            try await self?.whenLocal { myself in
                for await event in system.cluster.events {
                    try myself.receiveClusterEvent(event)
                }
            }
        }
    }

    internal func receiveClusterEvent(_ event: Cluster.Event) throws {
        let directive: DowningStrategyDirective = try self.strategy.onClusterEvent(event: event)
        self.interpret(directive: directive)
    }

    internal func interpret(directive: DowningStrategyDirective) {
        switch directive.underlying {
        case .markAsDown(let members):
            self.markAsDown(members: members)

        case let .startTimer(member, delay):
            self.log.trace("Start timer for member: \(member), delay: \(delay)")
            self.memberTimerTasks[member] = Task { [weak self] in
                try await self?.whenLocal { myself in
                    defer { myself.memberTimerTasks.removeValue(forKey: member) }

                    try await Task.sleep(until: .now + delay, clock: .continuous)

                    guard !Task.isCancelled else {
                        return
                    }
                    myself.onTimeout(member: member)
                }
            }

        case .cancelTimer(let member):
            self.log.trace("Cancel timer for member: \(member)")
            if let timerTask = self.memberTimerTasks.removeValue(forKey: member) {
                timerTask.cancel()
            }

        case .unchanged:
            ()  // nothing to be done
        }
    }

    internal func markAsDown(members: Set<Cluster.Member>) {
        for member in members {
            self.log.info(
                "Decide to [.down] member [\(member)]!",
                metadata: self.metadata(
                    [
                        "downing/node": .string("\(reflecting: member.node)"),
                        "member/status/previous": "\(member.status)",
                    ]
                )
            )
            self.actorSystem.cluster.down(member: member)
        }
    }

    internal func onTimeout(member: Cluster.Member) {
        let directive: DowningStrategyDirective = self.strategy.onTimeout(member)
        self.log.debug("Received timeout for [\(member)], resulting in: \(directive)")
        self.interpret(directive: directive)
    }
    internal func metadata(_ additional: Logger.Metadata) -> Logger.Metadata {
        self.metadata.merging(additional) { _, replacement in replacement }
    }
    deinit {
        print("\(Self.self) DEINIT")
        self.eventsListeningTask?.cancel()
    }
}
