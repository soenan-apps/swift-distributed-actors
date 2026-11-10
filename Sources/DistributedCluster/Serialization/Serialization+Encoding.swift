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
    /// Generate `Serialization.Manifest` and serialize the passed in message.
    ///
    /// - Parameters:
    ///   - message: The message intended to be serialized. Existence of an apropriate serializer should be ensured
    ///   before calling this method.
    ///   - file: The file path.
    ///   - line: The line number.
    /// - Returns: `Serialized` describing what serializer was used to serialize the value, and its serialized bytes
    /// - Throws: If no manifest could be created for the value, or a manifest was created however it selected
    ///   a serializer (by ID) that is not registered with the system, or the serializer failing to serialize the
    ///   message.
    public func serialize<Message>(
        _ message: Message,
        file: String = #filePath,
        line: UInt = #line
    ) throws -> Serialized {
        do {
            // The Any cast recovers the concrete runtime type of an erased generic argument.
            let messageType: Any.Type = type(of: message as Any)
            assert(
                messageType != Any.self,
                "Underlying message type resolved as Any.Type. This should never happen, please file a bug. "
                    + "Was: \(message)"
            )

            let manifest: Serialization.Manifest = try self.outboundManifest(messageType)

            traceLog_Serialization(
                "serialize(\(message), manifest: \(manifest))",
                file: #fileID,
                line: #line
            )

            let result: Serialization.Buffer
            if let predefinedSerializer: AnySerializer =
                (self.serializersLock.withReaderLock { self.serializers[ObjectIdentifier(messageType)] }) {
                result = try predefinedSerializer.trySerialize(message)
            } else if let makeSpecializedSerializer = self.settings.specializedSerializerMakers[manifest] {
                let serializer: AnySerializer = makeSpecializedSerializer(self.allocator)
                serializer.setSerializationContext(self.context)
                result = try serializer.trySerialize(message)
            } else if let encodableMessage = message as? Encodable {
                result = try self.encodeCodable(encodableMessage, manifest: manifest)
            } else {
                self.debugPrintSerializerTable(
                    header: "Unable to find serializer for manifest (\(manifest)),"
                        + "message type: \(String(reflecting: messageType))"
                )
                throw SerializationError(
                    .noSerializerRegisteredFor(
                        manifest: manifest,
                        hint: "Type: \(messageType), id: \(messageType), known serializers: \(self.serializers)"
                    )
                )
            }

            return Serialized(manifest: manifest, buffer: result)
        } catch {
            // enrich with location of the failed serialization
            throw SerializationError(.serializationError(error, file: file, line: line))
        }
    }

}
