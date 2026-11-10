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

extension GameUnit.Command {
    internal enum DiscriminatorKeys: String, Codable {
        case otherCommand = "otherCommand"
        case player = "player"
    }

    internal enum CodingKeys: String, CodingKey {
        case discriminator = "_case"
        case playerValue = "player_value"
    }

    internal init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: .discriminator) {
        case .player:
            let value: ActorRef<Player.Command> =
                try container.decode(ActorRef<Player.Command>.self, forKey: .playerValue)
            self = .player(value)

        case .otherCommand:
            self = .otherCommand
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .player(let value):
            try container.encode(DiscriminatorKeys.player, forKey: .discriminator)
            try container.encode(value, forKey: .playerValue)

        case .otherCommand:
            try container.encode(DiscriminatorKeys.player, forKey: .discriminator)
        }
    }
}
