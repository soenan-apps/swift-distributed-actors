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
import Foundation
import NIO
import NIOFoundationCompat

internal protocol ForSomeReasonNotCodable {}

internal struct DistributedAlgorithmExampleEnvelope<Payload: ForSomeReasonNotCodable>: Codable {
    internal enum CodingKeys: String, CodingKey {
        case payload = "payload"
        case payloadManifest = "payloadManifest"
    }

    internal let payload: Payload

    internal init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        guard let context = decoder.actorSerializationContext else {
            throw SerializationError(.missingSerializationContext(decoder, Self.self), file: #fileID, line: #line)
        }

        let manifest: Serialization.Manifest =
            try container.decode(Serialization.Manifest.self, forKey: .payloadManifest)
        let data: Data = try container.decode(Data.self, forKey: .payload)
        var buffer: ByteBuffer = context.serialization.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)

        // Option 1: raw bytes ----------------------------------------------------------------
        let decodedPayload: Payload = try context.serialization.deserialize(
            as: Payload.self, from: .nioByteBuffer(buffer), using: manifest
        )  // <1>

        self.payload = decodedPayload
    }

    internal func encode(to encoder: Encoder) throws {
        guard let context = encoder.actorSerializationContext else {
            throw SerializationError(.missingSerializationContext(encoder, self), file: #fileID, line: #line)
        }

        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        // Option 1: raw bytes ----------------------------------------------------------------
        let serialized: Serialization.Serialized = try context.serialization.serialize(self.payload)
        try container.encode(serialized.manifest, forKey: .payloadManifest)
        let data: Data
        switch serialized.buffer {
        case .data(let serializedData):
            data = serializedData

        case .nioByteBuffer(let buffer):
            guard let bufferedData = buffer.getData(at: 0, length: buffer.readableBytes) else {
                throw EncodingError.invalidValue(
                    buffer,
                    .init(codingPath: encoder.codingPath, debugDescription: "Serialized buffer range is invalid")
                )
            }
            data = bufferedData
        }
        try container.encode(data, forKey: .payload)
    }
}
