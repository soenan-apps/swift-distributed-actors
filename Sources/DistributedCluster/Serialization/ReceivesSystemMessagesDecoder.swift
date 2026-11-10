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

import Foundation  // for Codable
import NIO
import NIOFoundationCompat

internal enum ReceivesSystemMessagesDecoder {
    internal static func decode(from decoder: Decoder) throws -> ReceivesSystemMessages {
        guard let context = decoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(decoder, ReceivesSystemMessages.self)
        }

        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        let id: ActorID = try container.decode(ActorID.self)

        return context.resolveAddressableActorRef(identifiedBy: id)
    }
}
