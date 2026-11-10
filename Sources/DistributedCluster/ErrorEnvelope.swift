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

/// Transportable wrapper preserving codable errors or, otherwise, their type name.
public struct ErrorEnvelope: Error, Codable {
    /// An error whose original type and payload can be encoded.
    public typealias CodableError = Error & Codable
    internal enum CodingKeys: CodingKey {
        case error
        case manifest
    }

    private let codableError: CodableError

    /// The wrapped error, or a type-name representation for a noncodable error.
    public var error: Error {
        self.codableError
    }

    /// Wraps a codable error directly without nesting existing envelopes.
    public init(_ error: Error) {
        if let alreadyAnEnvelope = error as? Self {
            self = alreadyAnEnvelope
        } else if let serializableError = error as? CodableError {
            self.codableError = serializableError
        } else {
            // Carry only the error type; its textual description may contain private information.
            self.codableError = BestEffortStringError(representation: String(reflecting: type(of: error as Any)))
        }
    }

    /// Creates an envelope carrying the supplied description.
    public init(description: String) {
        self.codableError = BestEffortStringError(representation: description)
    }

    public init(from decoder: Decoder) throws {
        guard let context = decoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(decoder, Self.self)
        }

        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        let manifest: Serialization.Manifest = try container.decode(Serialization.Manifest.self, forKey: .manifest)
        let errorType: Any.Type = try context.summonType(from: manifest)

        guard let codableErrorType = errorType as? CodableError.Type else {
            throw SerializationError(
                .unableToDeserialize(hint: "Error type \(errorType) is not Codable")
            )
        }

        let errorDecoder: any Decoder = try container.superDecoder(forKey: .error)
        self.codableError = try codableErrorType.init(from: errorDecoder)
    }

    public func encode(to encoder: Encoder) throws {
        guard let context: Serialization.Context = encoder.actorSerializationContext else {
            throw SerializationError.missingSerializationContext(encoder, Self.self)
        }

        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            context.serialization.outboundManifest(type(of: self.codableError as Any)),
            forKey: .manifest
        )

        let errorEncoder: any Encoder = container.superEncoder(forKey: .error)
        try self.codableError.encode(to: errorEncoder)
    }
}
