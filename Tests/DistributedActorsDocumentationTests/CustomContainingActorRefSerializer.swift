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

import DistributedCluster

internal struct ContainsActorRef {
    internal let ref: ActorRef<String>
}

internal final class CustomContainingActorRefSerializer: Serializer<ContainsActorRef> {
    internal enum CustomCodingError: Error {
        case serializationContextNotAvailable
    }

    private let encodeID: (ActorID) throws -> Serialization.Buffer
    private let decodeID: (Serialization.Buffer) throws -> ActorID
    private var context: Serialization.Context?

    internal init(
        encodeID: @escaping (ActorID) throws -> Serialization.Buffer,
        decodeID: @escaping (Serialization.Buffer) throws -> ActorID
    ) {
        self.encodeID = encodeID
        self.decodeID = decodeID
    }

    override internal func setSerializationContext(_ context: Serialization.Context) {
        self.context = context  // <1>
    }

    override internal func serialize(_ message: ContainsActorRef) throws -> Serialization.Buffer {
        try self.encodeID(message.ref.id)
    }

    override internal func deserialize(from buffer: Serialization.Buffer) throws -> ContainsActorRef {
        let id: ActorID = try self.decodeID(buffer)
        guard let context = self.context else {
            throw CustomCodingError.serializationContextNotAvailable
        }

        let resolved: ActorRef<String> = context.resolveActorRef(identifiedBy: id)  // <2>
        return ContainsActorRef(ref: resolved)
    }
}
