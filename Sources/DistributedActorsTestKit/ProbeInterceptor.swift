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

/// Allows intercepting messages
public final class ProbeInterceptor<Message: Codable>: Interceptor<Message> {
    internal let probe: ActorTestProbe<Message>

    public init(probe: ActorTestProbe<Message>) {
        self.probe = probe
    }

    override public func interceptMessage(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        message: Message
    ) throws -> Behavior<Message> {
        self.probe.tell(message)
        return try target.interpretMessage(context: context, message: message)
    }
}
