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
    internal static func registerBuiltInMessages(in configuredSettings: inout Serialization.Settings) {
        configuredSettings.register(InvocationMessage.self, serializerID: .foundationJSON)
        configuredSettings.register(Int.self, hint: "i", serializerID: .specializedWithTypeHint)
        configuredSettings.registerSpecializedSerializer(
            Int.self,
            serializerID: .specializedWithTypeHint,
            hint: "i"
        ) { allocator in
            IntegerSerializer(Int.self, allocator)
        }
        configuredSettings.register(UInt.self, hint: "u", serializerID: .specializedWithTypeHint)
        configuredSettings.registerSpecializedSerializer(
            UInt.self,
            serializerID: .specializedWithTypeHint,
            hint: "u"
        ) { allocator in
            IntegerSerializer(UInt.self, allocator)
        }
        configuredSettings.registerSpecializedSerializer(
            String.self,
            serializerID: .specializedWithTypeHint,
            hint: "S"
        ) { allocator in
            StringSerializer(allocator)
        }
        configuredSettings.register(Int?.self, hint: "qI")
        configuredSettings.register(SystemMessages.self)
        configuredSettings.register(SystemMessages.ACK.self)
        configuredSettings.register(SystemMessages.NACK.self)
        configuredSettings.register(SystemMessageEnvelope.self)
        configuredSettings.register(Done.self)
        configuredSettings.register(Result<Done, ErrorEnvelope>.self)
        configuredSettings.register(
            Wire.Envelope.self,
            hint: Wire.Envelope.typeHint,
            serializerID: .protobufRepresentable,
            alsoRegisterActorRef: false
        )
        configuredSettings.register(ClusterShell.Message.self)
        configuredSettings.register(Cluster.Event.self)
        configuredSettings.register(Cluster.MembershipGossip.self)
        configuredSettings.register(GossipShell<Cluster.MembershipGossip, Cluster.MembershipGossip>.Message.self)
        configuredSettings.register(StringGossipIdentifier.self)
        configuredSettings.register(Receptionist.Message.self, serializerID: .doNotSerialize)
        configuredSettings.register(SWIM.PingResponse.self)
        configuredSettings.register(ActorID.self, serializerID: .foundationJSON)
        configuredSettings.register(ClusterSystem.ActorID.self, serializerID: .foundationJSON)
        configuredSettings.register(ReplicaID.self, serializerID: .foundationJSON)
        configuredSettings.register(VersionDot.self, serializerID: .protobufRepresentable)
        configuredSettings.register(VersionVector.self, serializerID: .protobufRepresentable)
    }
}
