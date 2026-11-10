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

// we should not add Codable conformance onto a stdlib type, but rather fix this in stdlib
extension Result: @retroactive Codable where Success: Codable, Failure: Codable {
    internal enum DiscriminatorKeys: String, Codable {
        case failure = "failure"
        case success = "success"
    }

    internal enum CodingKeys: String, CodingKey {
        case discriminator = "_case"
        case failureValue = "failure_value"
        case successValue = "success_value"
    }

    /// Decodes the existing result discriminator and its associated value.
    public init(from decoder: Swift.Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: .discriminator) {
        case .success:
            self = .success(try container.decode(Success.self, forKey: .successValue))

        case .failure:
            self = .failure(try container.decode(Failure.self, forKey: .failureValue))
        }
    }

    /// Encodes the result using the stable discriminator and payload keys.
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .success(success):
            try container.encode(DiscriminatorKeys.success, forKey: .discriminator)
            try container.encode(success, forKey: .successValue)

        case let .failure(failure):
            try container.encode(DiscriminatorKeys.failure, forKey: .discriminator)
            try container.encode(failure, forKey: .failureValue)
        }
    }
}
