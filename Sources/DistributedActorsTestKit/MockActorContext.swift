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

internal struct MockActorContextError: Error, CustomStringConvertible {
    internal var description: String {
        "MockActorContextError(A mock context can not be used to perform any real actions! "
            + "If you find yourself needing to perform assertions on an actor context please file a ticket.)"
    }
}

public final class MockActorContext<Message: Codable>: ActorContext<Message> {
    private let mockSystem: ClusterSystem
    private lazy var _log: Logger = .init(label: "\(type(of: self))")

    override public var system: ClusterSystem {
        self.mockSystem
    }

    override public var path: ActorPath {
        super.path
    }

    override public var name: String {
        "MockActorContext<\(Message.self)>"
    }

    override public var myself: ActorRef<Message> {
        self.system.deadLetters.adapted()
    }

    override public var log: Logger {
        get {
            self._log
        }
        set {
            self._log = newValue
        }
    }

    override public var props: Props {
        .init()  // mock impl
    }

    override public var children: Children {
        get {
            fatalError("Failed: \(MockActorContextError())")
        }
        set {
            _ = newValue
            fatalError("Failed: \(MockActorContextError())")
        }
    }

    public init(_ system: ClusterSystem) {
        self.mockSystem = system
    }

    @available(*, unavailable, message: "A mock context cannot perform actor operations")
    @discardableResult
    override public func watch<Watchee>(
        _: Watchee,
        with _: Message? = nil,
        file _: String = #filePath,
        line _: UInt = #line
    ) -> Watchee where Watchee: DeathWatchable {
        fatalError("Failed: \(MockActorContextError())")
    }

    @available(*, unavailable, message: "A mock context cannot perform actor operations")
    @discardableResult
    override public func unwatch<Watchee>(
        _: Watchee,
        file _: String = #filePath,
        line _: UInt = #line
    ) -> Watchee where Watchee: DeathWatchable {
        fatalError("Failed: \(MockActorContextError())")
    }

    @available(*, unavailable, message: "A mock context cannot perform actor operations")
    @discardableResult
    override public func spawn<M>(
        _: ActorNaming,
        _: Behavior<M>,
        props _: Props = Props(),
        file _: String = #filePath,
        line _: UInt = #line
    ) -> ActorRef<M>
    where M: Codable {
        fatalError("Failed: \(MockActorContextError())")
    }

    @available(*, unavailable, message: "A mock context cannot perform actor operations")
    @discardableResult
    override public func spawnWatch<M>(
        _: ActorNaming,
        _: Behavior<M>,
        props _: Props = Props(),
        file _: String = #filePath,
        line _: UInt = #line
    ) -> ActorRef<M>
    where M: Codable {
        fatalError("Failed: \(MockActorContextError())")
    }

    @available(*, unavailable, message: "A mock context cannot perform actor operations")
    override public func stop<M>(child _: ActorRef<M>) {
        fatalError("Failed: \(MockActorContextError())")
    }
}
