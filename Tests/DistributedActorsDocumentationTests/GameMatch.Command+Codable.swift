// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

// tag::imports[]

import DistributedCluster

extension GameMatch.Command {
    internal enum DiscriminatorKeys: String, Codable {
        case disconnectedPleaseStop = "disconnectedPleaseStop"
        case playerConnected = "playerConnected"
    }

    internal enum CodingKeys: String, CodingKey {
        case discriminator = "_case"
        case playerConnectedValue = "playerConnected_value"
    }

    internal init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: .discriminator) {
        case .playerConnected:
            let value: ActorRef<Player.Command> =
                try container.decode(ActorRef<Player.Command>.self, forKey: .playerConnectedValue)
            self = .playerConnected(value)

        case .disconnectedPleaseStop:
            self = .disconnectedPleaseStop
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .playerConnected(let value):
            try container.encode(DiscriminatorKeys.playerConnected, forKey: .discriminator)
            try container.encode(value, forKey: .playerConnectedValue)

        case .disconnectedPleaseStop:
            try container.encode(DiscriminatorKeys.disconnectedPleaseStop, forKey: .discriminator)
        }
    }
}
