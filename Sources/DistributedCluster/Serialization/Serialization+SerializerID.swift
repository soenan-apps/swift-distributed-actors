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

import SWIM

extension Serialization {
    /// Used to identify a type (or instance) of a `Serializer`.
    public struct SerializerID: ExpressibleByIntegerLiteral, Hashable, Comparable, CustomStringConvertible {

        /// ワイヤー上で使用する数値ID。
        public let value: UInt32

        public var description: String {
            switch self.value {
            case Self.doNotSerialize.value:
                return "serializerID:doNotSerialize(\(self.value))"

            case Self.protobufRepresentable.value:
                return "serializerID:ProtobufRepresentable(\(self.value))"

            case Self.specializedWithTypeHint.value:
                return "serializerID:specialized(\(self.value))"

            case Self.foundationJSON.value:
                return "serializerID:jsonCodable(\(self.value))"

            case Self.foundationPropertyListBinary.value:
                return "serializerID:foundationPropertyListBinary(\(self.value))"

            case Self.foundationPropertyListXML.value:
                return "serializerID:foundationPropertyListXML(\(self.value))"

            default:
                return "serializerID:\(self.value)"
            }
        }

        public init(integerLiteral value: UInt32) {
            self.init(value)
        }

        public init(_ id: UInt32) {
            self.value = id
        }

        public static func < (lhs: Serialization.SerializerID, rhs: Serialization.SerializerID) -> Bool {
            lhs.value < rhs.value
        }

        public static func == (lhs: Serialization.SerializerID, rhs: Serialization.SerializerID) -> Bool {
            lhs.value == rhs.value
        }
    }
}

extension Optional where Wrapped == Serialization.SerializerID {
    /// Use the default serializer, as configured in `Serialization.Settings.defaultSerializerID`.
    public static let `default`: Serialization.SerializerID? = nil
}

extension Serialization {
    /// Serializer IDs allocated for internal messages.
    ///
    /// Those messages are usually serialized using specialized serializers rather than the generic catch all Codable
    /// infrastructure,
    /// in order to allow fine grained evolution and payload size savings.
    internal enum ReservedID {
        internal static let SystemMessage: SerializerID = .doNotSerialize
        internal static let SystemMessageACK: SerializerID = .checkProtobufRepresentable(SystemMessages.ACK.self)
        internal static let SystemMessageNACK: SerializerID = .checkProtobufRepresentable(SystemMessages.NACK.self)
        internal static let SystemMessageEnvelope: SerializerID =
            .checkProtobufRepresentable(DistributedCluster.SystemMessageEnvelope.self)

        internal static let ActorID: SerializerID = .checkProtobufRepresentable(DistributedCluster.ActorID.self)

        internal static let ClusterShellMessage: SerializerID = .checkProtobufRepresentable(ClusterShell.Message.self)
        internal static let ClusterEvent: SerializerID = .checkProtobufRepresentable(Cluster.Event.self)

        internal static let SWIMPingResponse: SerializerID = .checkProtobufRepresentable(SWIM.PingResponse.self)

        // op log receptionist
        internal static let PushOps: SerializerID = .foundationJSON
        internal static let AckOps: SerializerID = .foundationJSON

        internal static let ErrorEnvelope: SerializerID = .foundationJSON
        internal static let BestEffortStringError: SerializerID = .foundationJSON
    }
}
