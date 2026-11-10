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

import Distributed
import Foundation

internal protocol AnyRemoteCallReply: Codable {
    associatedtype Value: Codable
    typealias CallID = ClusterSystem.CallID

    var callID: CallID { get }
    var value: Value? { get }
    var thrownError: (any Error & Codable)? { get }

    init(callID: CallID, value: Value)
    init<Err: Error & Codable>(callID: CallID, error: Err)
}

internal struct RemoteCallReply<Value: Codable>: AnyRemoteCallReply {
    internal typealias CallID = ClusterSystem.CallID

    internal enum CodingKeys: String, CodingKey {
        case callID = "cid"
        case value = "v"
        case wasThrow = "t"
        case thrownError = "e"
        case thrownErrorManifest = "em"
    }

    internal let callID: CallID
    internal let value: Value?
    internal let thrownError: (any Error & Codable)?

    internal init(callID: CallID, value: Value) {
        self.callID = callID
        self.value = value
        self.thrownError = nil
    }

    internal init<Err: Error & Codable>(callID: CallID, error: Err) {
        self.callID = callID
        self.value = nil
        self.thrownError = error
    }

    internal init(from decoder: Decoder) throws {
        guard let context = decoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(decoder, Self.self)
        }

        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.callID = try container.decode(CallID.self, forKey: .callID)

        let wasThrow: Bool = try container.decodeIfPresent(Bool.self, forKey: .wasThrow) ?? false
        if wasThrow {
            let errorManifest: Serialization.Manifest = try container.decode(
                Serialization.Manifest.self,
                forKey: .thrownErrorManifest
            )
            let summonedErrorType: Any.Type = try context.serialization.summonType(from: errorManifest)
            guard let errorAnyType = summonedErrorType as? (Error & Codable).Type else {
                throw SerializationError(
                    .notAbleToDeserialize(
                        hint: """
                            manifest type results in [\(summonedErrorType)] type, \
                            which is NOT \((Error & Codable).self)
                            """
                    )
                )
            }
            self.thrownError = try container.decode(errorAnyType, forKey: .thrownError)
            self.value = nil
        } else {
            self.value = try container.decode(Value.self, forKey: .value)
            self.thrownError = nil
        }
    }

    internal func encode(to encoder: Encoder) throws {
        guard let context = encoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(encoder, Self.self)
        }

        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.callID, forKey: .callID)

        if let thrownError = self.thrownError {
            try container.encode(true, forKey: .wasThrow)
            let errorManifest: Serialization.Manifest = try context.serialization.outboundManifest(
                type(of: thrownError)
            )
            try container.encode(thrownError, forKey: .thrownError)
            try container.encode(errorManifest, forKey: .thrownErrorManifest)
        } else {
            try container.encode(self.value, forKey: .value)
        }
    }

}
