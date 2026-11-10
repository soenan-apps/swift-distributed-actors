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
import DistributedCluster
import Logging

internal distributed actor Philosopher: CustomStringConvertible {
    private enum State: Equatable {
        case thinking
        case takingForks(leftTaken: Bool, rightTaken: Bool)
        case eating
    }

    private let name: String
    private lazy var log: Logger = .init(actor: self)

    private let leftFork: Fork
    private let rightFork: Fork
    private var state: State = .thinking

    internal init(name: String, leftFork: Fork, rightFork: Fork, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.name = name
        self.leftFork = leftFork
        self.rightFork = rightFork

        Task {
            await self.whenLocal { myself in
                myself.log.info("\(myself.name) joined the table!")
                myself.think()
            }
        }
    }

    internal distributed func think() {
        if case let .takingForks(leftIsTaken, rightIsTaken) = self.state {
            if leftIsTaken {
                Task {
                    await self.returnFork(leftFork)
                }
            }

            if rightIsTaken {
                Task {
                    await self.returnFork(rightFork)
                }
            }
        }

        self.state = .thinking
        Task {
            do {
                try await Task.sleep(until: .now + .seconds(1), clock: .continuous)
                await self.attemptToTakeForks()
            } catch {
                self.log.warning("Thinking interrupted: \(error)")
            }
        }
        self.log.info("\(self.name) is thinking...")
    }

    internal distributed func attemptToTakeForks() async {
        guard self.state == .thinking else {
            self.log.error("\(self.name) tried to take a fork but was not in the thinking state!")
            return
        }

        self.state = .takingForks(leftTaken: false, rightTaken: false)

        do {
            let tookRight: Bool = try await self.rightFork.take()
            guard tookRight else {
                self.think()
                return
            }
            self.forkTaken(self.rightFork)

            let tookLeft: Bool = try await self.leftFork.take()
            guard tookLeft else {
                self.think()
                return
            }
            self.forkTaken(self.leftFork)
        } catch {
            self.log.info("\(self.name) wasn't able to take both forks!")
            self.think()
        }
    }

    /// Message sent to oneself after a timer exceeds and we're done `eating` and can become `thinking` again.
    internal distributed func stopEating() {
        self.log.info("\(self.name) is done eating and replaced both forks!")
        Task {
            await self.returnFork(self.leftFork)
        }
        Task {
            await self.returnFork(self.rightFork)
        }
        self.think()
    }

    private func forkTaken(_ fork: Fork) {
        if self.state == .thinking {  // We couldn't get the first fork and have already gone back to thinking.
            Task { await self.returnFork(fork) }
            return
        }

        guard case let .takingForks(leftForkIsTaken, rightForkIsTaken) = self.state else {
            self.log.error(
                "Received fork \(fork) but was not in .takingForks state. State was \(self.state)! Ignoring..."
            )
            Task { await self.returnFork(fork) }
            return
        }

        switch fork {
        case self.leftFork:
            self.log.info("\(self.name) received their left fork!")
            self.state = .takingForks(leftTaken: true, rightTaken: rightForkIsTaken)

        case self.rightFork:
            self.log.info("\(self.name) received their right fork!")
            self.state = .takingForks(leftTaken: leftForkIsTaken, rightTaken: true)

        default:
            self.log.error("Received unknown fork! Got: \(fork). Known forks: \(self.leftFork), \(self.rightFork)")
        }

        if case .takingForks(true, true) = self.state {
            becomeEating()
        }
    }

    private func becomeEating() {
        self.state = .eating
        self.log.notice("\(self.name) began eating!")
        Task {
            do {
                try await Task.sleep(until: .now + .seconds(3), clock: .continuous)
                self.stopEating()
            } catch {
                self.log.warning("Eating interrupted: \(error)")
            }
        }
    }

    private func returnFork(_ fork: Fork) async {
        do {
            try await fork.putBack()
            self.log.info("\(self.name) put back fork \(fork)!")
        } catch {
            self.log.warning("Failed putting back fork \(fork): \(error)")
        }
    }
}
