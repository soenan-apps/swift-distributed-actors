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
import NIO
import SwiftProtobuf

import struct Foundation.Data

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: ACK / NACK

extension SystemMessages.ACK: InternalProtobufRepresentable {
    internal typealias ProtobufRepresentation = _ProtoSystemMessageACK

    internal init(fromProto proto: _ProtoSystemMessageACK, context _: Serialization.Context) {
        self.sequenceNr = proto.sequenceNr
    }

    internal func toProto(context _: Serialization.Context) -> _ProtoSystemMessageACK {
        var proto: _ProtoSystemMessageACK = _ProtoSystemMessageACK()
        proto.sequenceNr = self.sequenceNr
        return proto
    }
}

extension SystemMessages.NACK: InternalProtobufRepresentable {
    internal typealias ProtobufRepresentation = _ProtoSystemMessageNACK

    internal init(fromProto proto: _ProtoSystemMessageNACK, context _: Serialization.Context) {
        self.sequenceNr = proto.sequenceNr
    }

    internal func toProto(context _: Serialization.Context) -> _ProtoSystemMessageNACK {
        var proto: _ProtoSystemMessageNACK = _ProtoSystemMessageNACK()
        proto.sequenceNr = self.sequenceNr
        return proto
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: SystemMessageEnvelope

extension SystemMessageEnvelope: InternalProtobufRepresentable {
    internal typealias ProtobufRepresentation = _ProtoSystemMessageEnvelope

    internal init(fromProto proto: _ProtoSystemMessageEnvelope, context: Serialization.Context) throws {
        self.sequenceNr = proto.sequenceNr
        self.message = try .init(fromProto: proto.message, context: context)
    }

    internal func toProto(context: Serialization.Context) throws -> _ProtoSystemMessageEnvelope {
        var proto: _ProtoSystemMessageEnvelope = _ProtoSystemMessageEnvelope()
        proto.sequenceNr = self.sequenceNr
        proto.message = try self.message.toProto(context: context)
        return proto
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: SystemMessage

extension SystemMessages: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoSystemMessage

    public init(fromProto proto: _ProtoSystemMessage, context: Serialization.Context) throws {
        guard let payload = proto.payload else {
            throw SerializationError(
                .missingField("payload", type: String(describing: SystemMessages.self))
            )
        }

        switch payload {
        case .watch(let watchPayload):
            guard watchPayload.hasWatchee else {
                throw SerializationError(.missingField("watchee", type: "SystemMessage.watch"))
            }
            guard watchPayload.hasWatcher else {
                throw SerializationError(.missingField("watcher", type: "SystemMessage.watch"))
            }

            let watcheeID: ActorID = try .init(fromProto: watchPayload.watchee, context: context)
            let watchee: AddressableActorRef = context.resolveAddressableActorRef(identifiedBy: watcheeID)

            let watcherID: ActorID = try .init(fromProto: watchPayload.watcher, context: context)
            let watcher: AddressableActorRef = context.resolveAddressableActorRef(identifiedBy: watcherID)

            self = .watch(watchee: watchee, watcher: watcher)

        case .unwatch(let unwatchPayload):
            guard unwatchPayload.hasWatchee else {
                throw SerializationError(.missingField("watchee", type: "SystemMessage.unwatch"))
            }
            guard unwatchPayload.hasWatcher else {
                throw SerializationError(.missingField("watcher", type: "SystemMessage.unwatch"))
            }

            let watcheeID: ActorID = try .init(fromProto: unwatchPayload.watchee, context: context)
            let watchee: AddressableActorRef = context.resolveAddressableActorRef(identifiedBy: watcheeID)

            let watcherID: ActorID = try .init(fromProto: unwatchPayload.watcher, context: context)
            let watcher: AddressableActorRef = context.resolveAddressableActorRef(identifiedBy: watcherID)

            self = .watch(watchee: watchee, watcher: watcher)

        case .terminated(let terminatedPayload):
            guard terminatedPayload.hasRef else {
                throw SerializationError(
                    .missingField("ref", type: "SystemMessage.terminated")
                )
            }
            // it is known dead, optimize the resolve?
            let ref: AddressableActorRef = try context.resolveAddressableActorRef(
                identifiedBy: .init(fromProto: terminatedPayload.ref, context: context)
            )
            self = .terminated(
                ref: ref,
                existenceConfirmed: terminatedPayload.existenceConfirmed,
                idTerminated: terminatedPayload.idTerminated
            )
        }
    }

    public func toProto(context: Serialization.Context) throws -> _ProtoSystemMessage {
        var proto: _ProtoSystemMessage = _ProtoSystemMessage()
        switch self {
        case let .watch(watchee, watcher):
            var watch: _ProtoSystemMessage_Watch = _ProtoSystemMessage_Watch()
            watch.watchee = try watchee.id.toProto(context: context)
            watch.watcher = try watcher.id.toProto(context: context)
            proto.payload = .watch(watch)

        case let .unwatch(watchee, watcher):
            var unwatch: _ProtoSystemMessage_Unwatch = _ProtoSystemMessage_Unwatch()
            unwatch.watchee = try watchee.id.toProto(context: context)
            unwatch.watcher = try watcher.id.toProto(context: context)
            proto.payload = .unwatch(unwatch)

        case let .terminated(ref, existenceConfirmed, idTerminated):
            var terminated: _ProtoSystemMessage_Terminated = _ProtoSystemMessage_Terminated()
            terminated.ref = try ref.id.toProto(context: context)
            terminated.existenceConfirmed = existenceConfirmed
            terminated.idTerminated = idTerminated
            proto.payload = .terminated(terminated)

        case .carrySignal(let signal):
            throw SerializationError(
                .nonTransportableMessage(type: "SystemMessage.carrySignal(\(signal))")
            )

        case .start:
            throw SerializationError(.nonTransportableMessage(type: "SystemMessage.start"))

        case .nodeTerminated:
            throw SerializationError(
                .nonTransportableMessage(type: "SystemMessage.idTerminated")
            )

        case .childTerminated:
            throw SerializationError(
                .nonTransportableMessage(type: "SystemMessage.childTerminated")
            )

        case .resume:
            throw SerializationError(.nonTransportableMessage(type: "SystemMessage.resume"))

        case .stop:
            throw SerializationError(.nonTransportableMessage(type: "SystemMessage.stop"))

        case .tombstone:
            throw SerializationError(
                .nonTransportableMessage(type: "SystemMessage.tombstone")
            )
        }
        return proto
    }
}
