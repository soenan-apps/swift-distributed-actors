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

extension ActorTestProbe: ReceivesMessages {
    public var id: ActorID {
        self.exposedRef.id
    }

    public func tell(_ message: Message, file: String = #filePath, line: UInt = #line) {
        self.exposedRef.tell(message, file: file, line: line)
    }
}
// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: TestProbes can intercept all messages send to a Behavior
extension ActorTestProbe {
    /// Copies every intercepted user message to this probe before delivery.
    public func interceptAllMessages(sentTo behavior: Behavior<Message>) -> Behavior<Message> {
        let interceptor: Interceptor<Message> = ProbeInterceptor(probe: self)
        return .intercept(behavior: behavior, with: interceptor)
    }
}
