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
    /// Deserialize a given payload as the expected type, using the passed type and manifest.
    ///
    /// - Parameters:
    ///   - messageType: expected type that the deserialized message should be
    ///   - serialized: `Serialized` containing the manifest used to identify which serializer should be used to
    ///   deserialize the bytes and the serialized bytes of the message
    ///   - file: The file path.
    ///   - line: The line number.
    public func deserialize<T>(
        as messageType: T.Type,
        from serialized: Serialized,
        file: String = #filePath,
        line: UInt = #line
    ) throws -> T {
        try self.deserialize(
            as: messageType,
            from: serialized.buffer,
            using: serialized.manifest,
            file: file,
            line: line
        )
    }

    /// Deserialize a given payload as the expected type, using the passed type and manifest.
    ///
    /// - Parameters:
    ///   - messageType: expected type that the deserialized message should be
    ///   - buffer: `Buffer` containing the serialized bytes of the message
    ///   - manifest: `Manifest` used to identify which serializer should be used to deserialize the bytes (json?
    ///   protobuf? other?)
    ///   - file: The file path.
    ///   - line: The line number.
    public func deserialize<T>(
        as messageType: T.Type,
        from buffer: Serialization.Buffer,
        using manifest: Serialization.Manifest,
        file: String = #filePath,
        line: UInt = #line
    ) throws -> T {
        guard messageType != Any.self else {
            // most likely deadLetters is trying to deserialize (!), and it only has an `Any` in hand.
            // let's use the manifest to invoke the right serializer, however
            return fatalErrorBacktrace(
                "ATTEMPT TO DESERIALIZE FROM DEAD LETTERS? payload: \(buffer)",
                file: #file,
                line: #line
            )
        }

        let deserializedAny: Any = try self.deserializeAny(from: buffer, using: manifest, file: file, line: line)
        if let deserialized = deserializedAny as? T {
            return deserialized
        }
        throw SerializationError(
            .serializationError(
                SerializationError(
                    .unableToDeserialize(
                        hint: "Deserialized value is NOT an instance of \(String(reflecting: T.self)), "
                            + "was: \(deserializedAny)"
                    )
                ),
                file: file,
                line: line
            )
        )
    }

    /// Deserialize a given payload as the expected type, using the passed manifest.
    ///
    /// Note that the deserialized message will be either correctly matching the type summoned from the manifest,
    /// or deserialization will fail. The returned type however will always be `Any`, and casting to the "expected type"
    /// should be performed elsewhere.
    ///
    /// This might seem strange, however enables a core ability: to deserialize refs where we do not have a statically
    /// known `Message`
    /// type anymore, e.g. when the recipient of a message has already terminated (and thus we "lost" the `Message` type
    /// available statically),
    /// yet we still want to deserialize the message, however have no need to cast it to the "right type" as our only
    /// reason to deserialize it
    /// is to carry it as an `Any` inside a `DeadLetter` notification.
    ///
    /// - Parameters:
    ///   - buffer: `Buffer` containing the serialized bytes of the message
    ///   - manifest: `Manifest` used identify the decoder as well as summon the Type of the message. The resulting
    ///   message is NOT cast to the summoned type.
    ///   - file: The file path.
    ///   - line: The line number.
    public func deserializeAny(
        from buffer: Serialization.Buffer,
        using manifest: Serialization.Manifest,
        file: String = #filePath,
        line: UInt = #line
    ) throws -> Any {
        do {
            // Manifest type may be used to summon specific instances of types from the manifest
            // even if the expected type is some `Outer` type (e.g. when we sent a sub class).
            let manifestMessageType: Any.Type = try self.summonType(from: manifest)
            let manifestMessageTypeID: ObjectIdentifier = ObjectIdentifier(manifestMessageType)

            let result: Any
            if let makeSpecializedSerializer = self.settings.specializedSerializerMakers[manifest] {
                let specializedSerializer: AnySerializer = makeSpecializedSerializer(self.allocator)
                specializedSerializer.setSerializationContext(self.context)
                result = try specializedSerializer.tryDeserialize(buffer)
            } else if let decodableMessageType = manifestMessageType as? Decodable.Type {
                result = try self.decodeCodable(decodableMessageType, from: buffer, manifest: manifest)
            } else {
                guard
                    let serializer: AnySerializer =
                        (self.serializersLock.withReaderLock {
                            self.serializers[manifestMessageTypeID]
                        })
                else {
                    self.debugPrintSerializerTable(
                        header: "Unable to find serializer for manifest (\(manifest)),"
                            + "message type: \(String(reflecting: manifestMessageType))"
                    )
                    throw SerializationError(
                        .noSerializerRegisteredFor(
                            manifest: manifest,
                            hint: "Manifest Type: \(manifestMessageType), id: \(manifestMessageTypeID), "
                                + "known serializers: \(self.serializers)"
                        )
                    )
                }

                result = try serializer.tryDeserialize(buffer)
            }

            return result
        } catch {
            // enrich with location of the failed serialization
            throw SerializationError(.serializationError(error, file: file, line: line))
        }
    }

    /// Validates serialization round-trip is possible for given message.
    ///
    /// Messages marked with `SkipSerializationVerification` are except from this verification.
    public func verifySerializable<Message: Codable>(message: Message) throws {
        switch message {
        case is NotActuallyCodableMessage:
            return  // skip

        default:
            let serialized: Serialized = try self.serialize(message)
            do {
                _ = try self.deserialize(as: Message.self, from: serialized)
                self.log.debug("Serialization verification passed for: [\(type(of: message as Any))]")
                // checking if the deserialized is equal to the passed in is a bit tricky,
                // so we only check if the round trip invocation was possible at all or not.
            } catch {
                throw SerializationError(
                    .unableToDeserialize(
                        hint: "verifySerializable failed, manifest: \(serialized.manifest), "
                            + "message: \(message), error: \(error)"
                    )
                )
            }
        }
    }
}
