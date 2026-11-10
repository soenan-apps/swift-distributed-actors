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
import NIO
import NIOSSL
import ServiceDiscovery
import SWIM

import class Foundation.ProcessInfo

internal enum AutomaticActorMetadataKind: Hashable {
    case typeName
}

/// Configures default actor id metadta behavior, like which metadata should be propagated cross process and which not.
internal struct ActorIDMetadataSettings {
    /// Metadata that the actor system can add automatically.
    public struct AutoIDMetadata {
        /// Tags each actor with a human-readable type name.
        internal static let typeName: Self = Self(underlying: .typeName)

        internal var underlying: AutomaticActorMetadataKind
    }

    internal static var `default`: Self {
        .init()
    }

    /// List of metadata which the system should automatically include in an `ActorID` for types it manages.
    internal var autoIncludedMetadata: [AutoIDMetadata] = []

    /// What type of tags, known and defined by the cluster system itself, should be automatically propagated.
    /// User-defined tags require ``encodeCustomMetadata`` and ``decodeCustomMetadata`` implementations.
    internal var propagateMetadata: Set<String> = [
        ActorMetadataKeys.defaultInstance.path.id,
        ActorMetadataKeys.defaultInstance.type.id,
        ActorMetadataKeys.defaultInstance.wellKnown.id,
    ]

    internal var encodeCustomMetadata:
        (ActorMetadata, inout KeyedEncodingContainer<ActorCoding.MetadataKeys>) throws -> Void = { _, _ in () }

    internal var decodeCustomMetadata:
        (KeyedDecodingContainer<ActorCoding.MetadataKeys>, ActorMetadata) throws -> Void = { _, _ in () }
}
