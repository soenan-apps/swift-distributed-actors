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
    /// Eagerly allocates serializer instances for configured (in settings) types and manifests.
    /// This allows us to lessen the contention on spawning things (as they also ensure serializers),
    /// as well as register "specific" serializers immediately which is plenty important (as those are allowed
    /// to not carry type hints in their manifests, and just ride on the serializer IDs).
    internal func ensureAllRegisteredSerializers() throws {
        // all non-codable types are specialized types; register specific serializer instances for them early
        for typeKey in self.settings.typeToManifestRegistry.keys {
            try typeKey.ensureSerializer(self)
        }

        #if SACT_TRACE_SERIALIZATION
        self.serializersLock.withReaderLock {
            for serializer in self.serializers {
                traceLog_Serialization(
                    "Eagerly registered serializer: \(serializer)",
                    file: #fileID,
                    line: #line
                )
            }
        }
        #endif
    }

    /// 登録済みマニフェストからメッセージ型のシリアライザーを確保する。
    public func ensureSerializer<Message: Codable>(
        _ type: Message.Type,
        file _: String = #filePath,
        line _: UInt = #line
    ) throws {
        let oid: ObjectIdentifier = ObjectIdentifier(type)

        // 1. check if this type already has a serializer registered, bail out quickly if so
        self.serializersLock.withReaderLock {
            if self.serializers[oid] != nil {
                return
            }
        }

        // 2. seems this type was not registered yet, so we need to store the appropriate serializer for it
        try self.serializersLock.withWriterLock {
            // 2.1. check again, in case someone had just stored a serializer while we were waiting for the writer lock
            if self.serializers[oid] != nil {
                return
            }

            // 2.2. obtain the manifest that we would use for this type, as it carries the right serializerID
            let manifest: Serialization.Manifest = try self.outboundManifest(type)

            // 2.3. create and store the appropriate serializer
            do {
                self.serializers[oid] = try self.makeCodableSerializer(type, manifest: manifest)
            } catch let error as SerializationError {
                // some types are specifically marked as "do not serialize" and we should ignore failures
                // to create serializers for them. E.g. this cna happen for a "top level protocol"
                // which by itself is never sent/serialized, but subclasses of it might.
                if case .noNeedToEnsureSerializer = error.underlying.error {
                    return
                }
                throw error
            } catch {
                // all other errors are real and should be escalated
                throw error
            }

            traceLog_Serialization(
                "Registered [\(manifest)] for [\(reflecting: type)]",
                file: #fileID,
                line: #line
            )
        }
    }

    internal func makeCodableSerializer<Message: Codable>(
        _ type: Message.Type,
        manifest: Manifest
    ) throws -> AnySerializer {
        switch manifest.serializerID {
        case .doNotSerialize:
            throw SerializationError(.noNeedToEnsureSerializer)

        case Self.SerializerID.specializedWithTypeHint:
            guard let make = self.settings.specializedSerializerMakers[manifest] else {
                throw SerializationError(
                    .unableToMakeSerializer(
                        hint: """
                            Type: \(String(reflecting: type)), \
                            Manifest: \(manifest), \
                            Specialized serializer makers: \(self.settings.specializedSerializerMakers)
                            """
                    )
                )
            }

            let serializer: AnySerializer = make(self.allocator)
            serializer.setSerializationContext(self.context)
            return serializer

        case Self.SerializerID.foundationJSON:
            let serializer: JSONCodableSerializer<Message> = .init()
            serializer.setSerializationContext(self.context)
            return serializer

        case Self.SerializerID.foundationPropertyListBinary,
            Self.SerializerID.foundationPropertyListXML:
            let format: PropertyListSerialization.PropertyListFormat =
                manifest.serializerID == .foundationPropertyListBinary ? .binary : .xml

            let serializer: PropertyListCodableSerializer<Message> = .init(format: format)
            serializer.setSerializationContext(self.context)
            return serializer

        case Self.SerializerID.protobufRepresentable:
            return TopLevelBytesBlobSerializer<Message>(allocator: self.allocator, context: self.context)

        default:
            throw SerializationError(
                .unableToMakeSerializer(
                    hint: "Not recognized serializerID: \(manifest.serializerID), in manifest: [\(manifest)] for "
                        + "type [\(type)]"
                )
            )
        }
    }
}
