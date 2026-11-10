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

import Logging

@usableFromInline
internal enum ProcessingAction<Message: Codable> {
    case closure(ActorClosureCarry)
    case continuation(() throws -> Behavior<Message>)
    case message(Message)
    case signal(Signal)
    case start
    case subMessage(SubMessageCarry)

    @usableFromInline internal var type: ProcessingType {
        switch self {
        case .start:
            return .start

        case .message:
            return .message

        case .signal:
            return .signal

        case .closure:
            return .closure

        case .continuation:
            return .continuation

        case .subMessage:
            return .subMessage
        }
    }
}
