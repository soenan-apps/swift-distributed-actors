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

// tag::serialize_manifest_any[]
import DistributedCluster
import Foundation
import NIO
import NIOFoundationCompat

// end::serialize_manifest_any[]

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Serialization example - Codable messages

// tag::serialization_codable_messages[]
internal enum ParkingSpotStatus: String, Codable {
    case available = "available"
    case taken = "taken"
}

// end::serialization_codable_messages[]

// tag::serialization_codable_manual_enum_assoc[]
internal struct ParkingTicket: Codable {}

internal enum ParkingTicketMessage: Codable {
    case issued(ParkingTicket)
    case pay(ParkingTicket, amount: Int)
}

// end::serialization_codable_manual_enum_assoc[]

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Serialization example - protobuf messages

// tag::serialization_protobuf_messages[]
internal enum ParkingGarageStatus: ProtobufRepresentable {
    case available
    case full
}

// end::serialization_protobuf_messages[]

// tag::serialization_protobuf_representable[]

// end::serialization_protobuf_representable[]

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Serialization example - custom messages

// tag::serialization_custom_messages[]
internal enum CustomlyEncodedMessage: Codable, NotActuallyCodableMessage {
    case available
    case taken
}

// end::serialization_custom_messages[]

internal class SerializationDocExamples {
    internal struct MyMessage: Codable {}
    internal struct OtherGenericMessage<M: Codable>: Codable {}

    internal lazy var exampleSystem: ClusterSystem = undefined(hint: "Examples, not intended to be run")

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Serialized Codable messages

    internal func prepare_system_codable() async {
        // tag::prepare_system_codable[]
        let system: ClusterSystem = await ClusterSystem("CodableExample") { settings in
            settings.serialization.register(ParkingSpotStatus.self)
        }
        // end::prepare_system_codable[]
        _ = system  // silence not-used warnings
    }

    internal func sending_serialized_codable_messages() {
        let spotAvailable: Bool = false
        // tag::sending_serialized_codable_messages[]
        func replyParkingSpotAvailability(driver: ActorRef<ParkingSpotStatus>) {
            if spotAvailable {
                driver.tell(.available)
            } else {
                driver.tell(.taken)
            }
        }
        // end::sending_serialized_codable_messages[]
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Serialized protobuf messages

    internal func prepare_system_protobuf() async {
        // tag::prepare_system_protobuf[]
        let system: ClusterSystem = await ClusterSystem("ProtobufExample") { settings in
            settings.serialization.register(ParkingGarageStatus.self)
        }
        // end::prepare_system_protobuf[]
        _ = system  // silence not-used warnings
    }

    internal func sending_serialized_protobuf_messages() {
        let garageAvailable: Bool = false
        // tag::sending_serialized_protobuf_messages[]
        func replyParkingGarageAvailability(driver: ActorRef<ParkingGarageStatus>) {
            if garageAvailable {
                driver.tell(.available)
            } else {
                driver.tell(.full)
            }
        }
        // end::sending_serialized_protobuf_messages[]
    }

    // ==== --------------------------------------------------------------------------------------------------------
    // MARK: Serialized custom messages

    internal func prepare_system_custom() async {
        // tag::prepare_system_custom[]
        let system: ClusterSystem = await ClusterSystem("CustomSerializerExample") { settings in
            settings.serialization.registerSpecializedSerializer(
                CustomlyEncodedMessage.self,
                serializerID: 1_001
            ) { allocator in
                CustomlyEncodedSerializer(allocator)
            }
        }
        // end::prepare_system_custom[]
        _ = system  // silence not-used warnings
    }

    internal func serialization_specific_coder() async {
        // tag::serialization_specific_coder[]
        let system: ClusterSystem = await ClusterSystem("CustomizeCoderExample") { settings in
            settings.serialization.register(MyMessage.self, serializerID: .foundationJSON)
        }
        // end::serialization_specific_coder[]
        _ = system  // silence not-used warnings
    }

    internal func serialization_register_types() async {
        // tag::serialization_register_types[]
        let system: ClusterSystem = await ClusterSystem("RegisteringTypes") { settings in
            // settings.serialization.insecureSerializeNotRegisteredMessages = false (default in RELEASE mode)
            settings.serialization.register(MyMessage.self)
            settings.serialization.register(OtherGenericMessage<Int>.self)
        }
        // end::serialization_register_types[]
        _ = system  // silence serialization_register_types-used warnings
    }
}
