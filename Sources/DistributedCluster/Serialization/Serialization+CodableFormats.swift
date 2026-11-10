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

import CDistributedActorsMailbox
import Distributed
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf
import SWIM

extension Serialization {
    internal func encodeCodable<Message: Encodable>(
        _ message: Message,
        manifest: Manifest
    ) throws -> Buffer {
        switch manifest.serializerID {
        case .specializedWithTypeHint:
            throw SerializationError(
                .unableToMakeSerializer(
                    hint:
                        """
                        Manifest hints at using specialized serializer for \(message), \
                        however no specialized serializer could be made for it! Manifest: \(manifest), \
                        known specializedSerializerMakers: \(self.settings.specializedSerializerMakers)
                        """
                )
            )

        case .protobufRepresentable:
            let encoder: TopLevelProtobufBlobEncoder = TopLevelProtobufBlobEncoder(allocator: self.allocator)
            encoder.userInfo[.actorSystemKey] = self.context.system
            encoder.userInfo[.actorSerializationContext] = self.context
            return try message.encodeSerialized(using: encoder)

        case .foundationJSON:
            let encoder: JSONEncoder = JSONEncoder()
            encoder.userInfo[.actorSystemKey] = self.context.system
            encoder.userInfo[.actorSerializationContext] = self.context
            return .data(try message.encodeSerialized(using: encoder))

        case .foundationPropertyListBinary:
            let encoder: PropertyListEncoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            encoder.userInfo[.actorSystemKey] = self.context.system
            encoder.userInfo[.actorSerializationContext] = self.context
            return .data(try message.encodeSerialized(using: encoder))

        case .foundationPropertyListXML:
            let encoder: PropertyListEncoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            encoder.userInfo[.actorSystemKey] = self.context.system
            encoder.userInfo[.actorSerializationContext] = self.context
            return .data(try message.encodeSerialized(using: encoder))

        case let otherSerializerID:
            throw SerializationError(
                .unableToMakeSerializer(
                    hint: "SerializerID: \(otherSerializerID), messageType: \(type(of: message)), manifest: \(manifest)"
                )
            )
        }
    }

    internal func decodeCodable<Message: Decodable>(
        _ messageType: Message.Type,
        from buffer: Buffer,
        manifest: Manifest
    ) throws -> Message {
        switch manifest.serializerID {
        case .specializedWithTypeHint:
            throw SerializationError(
                .unableToMakeSerializer(
                    hint:
                        """
                        Manifest hints at using specialized serializer for manifest \(manifest), \
                        however no specialized serializer could be made for it! \
                        Known specializedSerializerMakers: \(self.settings.specializedSerializerMakers)
                        """
                )
            )

        case .protobufRepresentable:
            let decoder: TopLevelProtobufBlobDecoder = TopLevelProtobufBlobDecoder()
            decoder.userInfo[.actorSystemKey] = self.context.system
            decoder.userInfo[.actorSerializationContext] = self.context
            return try messageType.decodeSerialized(from: buffer, using: decoder)

        case .foundationJSON:
            let decoder: JSONDecoder = JSONDecoder()
            decoder.userInfo[.actorSystemKey] = self.context.system
            decoder.userInfo[.actorSerializationContext] = self.context
            return try messageType.decodeSerialized(from: buffer, using: decoder)

        case .foundationPropertyListBinary:
            let decoder: PropertyListDecoder = PropertyListDecoder()
            decoder.userInfo[.actorSystemKey] = self.context.system
            decoder.userInfo[.actorSerializationContext] = self.context
            return try messageType.decodeSerialized(from: buffer, using: decoder, format: .binary)

        case .foundationPropertyListXML:
            let decoder: PropertyListDecoder = PropertyListDecoder()
            decoder.userInfo[.actorSystemKey] = self.context.system
            decoder.userInfo[.actorSerializationContext] = self.context
            return try messageType.decodeSerialized(from: buffer, using: decoder, format: .xml)

        case let otherSerializerID:
            throw SerializationError(
                .unableToMakeSerializer(
                    hint: "SerializerID: \(otherSerializerID), messageType: \(messageType), manifest: \(manifest)"
                )
            )
        }
    }

}
