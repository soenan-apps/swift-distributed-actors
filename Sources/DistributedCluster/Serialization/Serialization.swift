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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Serialization sub-system

/// Actor messaging specialized serialization engine.
///
/// For the most part, serialization should remain fully transparent to end users while using `Codable`,
/// and remain customizable and evolve-able by registering custom `Serialization.Manifest`s.
///
/// Allows for (de-)serialization of messages as configured per actor system,
/// using `Codable` or other custom serialization engines.
///
/// The serialization infrastructure automatically registers and maintains well-typed serializer instances
/// for any kind of Message type that is possible to be received by any spawned `Actor`, sub-receive, `Gossip` instance
/// etc.
///
public class Serialization {
    internal let log: Logger
    internal let settings: Serialization.Settings
    internal let metadataSettings: ActorIDMetadataSettings

    /// Allocator used by the serialization infrastructure.
    /// Public only for access by other serialization work performed e.g. by other transports.
    public let allocator: ByteBufferAllocator

    @usableFromInline internal let metrics: ClusterSystemMetrics

    /// WARNING: This WILL be mutated during runtime!
    ///
    /// Each time an actor spawns, it may have to register its _specific_ type manifest with the serialization infra.
    /// This is because we are not able to express serializers over existentials like `Gossip<Something Codable>`,
    /// while such actors may of course spawn at will and share their refs with remotes.
    ///
    /// In order to allow us performing a deserialization of an incoming message to such actor, we need to be able to
    /// perform:
    /// manifest -> specific _serializer_ which has the specific T (which e.g. is known to be Codable)
    ///
    /// This is on purpose NOT keyed by `Manifest`, as manifest is type + serializer, and here we only care "does this
    /// type
    /// have a serializer, whatever it is." It is also important that we can _recover_ the type from the wire protocol,
    /// e.g. we carry the mangled name in `manifest.hint` and from that perform an `_typeByName` to get an `Any.Type`.
    /// It's unique identity is equal to what we use to index into this map.
    ///
    /// - Concurrency: Access MUST be protected by `serializersLock`
    internal var serializers: [ObjectIdentifier: AnySerializer] = [:]

    /// Used to protect `serializers`.
    internal var serializersLock: ReadWriteLock = ReadWriteLock()

    internal let context: Serialization.Context

    internal init(settings systemSettings: ClusterSystemSettings, system: ClusterSystem) throws {
        var configuredSettings: Serialization.Settings = systemSettings.serialization

        Self.registerBuiltInMessages(in: &configuredSettings)

        self.settings = configuredSettings
        self.metadataSettings = system.settings.actorMetadata
        self.metrics = system.metrics

        self.allocator = self.settings.allocator

        var serializationLog: Logger = system.log
        serializationLog[metadataKey: "node"] = .stringConvertible(systemSettings.bindNode)
        serializationLog[metadataKey: "actor/path"] = "/system/serialization"
        serializationLog.logLevel = systemSettings.logging.logLevel
        self.log = serializationLog

        self.context = Self.Context(
            log: serializationLog,
            system: system,
            allocator: self.allocator
        )

        // == eagerly ensure serializers for message types which would not otherwise be registered for some reason ----
        try self.ensureAllRegisteredSerializers()

        #if SACT_TRACE_SERIALIZATION
        self.debugPrintSerializerTable(header: "SACT_TRACE_SERIALIZATION: Registered serializers")
        #endif
    }

    @usableFromInline
    internal func debugPrintSerializerTable(header: String = "") {
        var table: String = "\(header)\n"
        let registeredSerializers: [ObjectIdentifier: AnySerializer] = self.serializersLock.withReaderLock {
            self.serializers
        }
        for (id, anySerializer) in registeredSerializers {
            table += "  Serializer (id:\(id)) = \(anySerializer)\n"
        }
        print("\(table)")
        self.log.debug("\(table)")
    }
}
