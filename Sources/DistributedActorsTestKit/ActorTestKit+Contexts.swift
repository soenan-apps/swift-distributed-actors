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
    /// Creates a _fake_ `ActorContext` which can be used to pass around to fulfil type argument requirements,
    /// however it DOES NOT have the ability to perform any of the typical actor context actions (such as spawning etc).
    public func makeFakeContext<M: Codable>(of _: M.Type = M.self) -> ActorContext<M> {
        MockActorContext(self.system)
    }

    /// Creates a _fake_ `ActorContext` which can be used to pass around to fulfil type argument requirements,
    /// however it DOES NOT have the ability to perform any of the typical actor context actions (such as spawning etc).
    public func makeFakeContext<M: Codable>(for _: Behavior<M>) -> ActorContext<M> {
        self.makeFakeContext(of: M.self)
    }
}
