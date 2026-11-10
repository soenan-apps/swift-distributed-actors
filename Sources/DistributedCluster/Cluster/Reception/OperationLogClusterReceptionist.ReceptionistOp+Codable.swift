// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

private enum ReceptionistOpDiscriminator: String, Codable {
    case register = "register"
    case remove = "remove"
}

private enum ReceptionistOpCodingKeys: String, CodingKey {
    case discriminator = "_case"
    case id = "id"
    case key = "key"
}

extension OperationLogClusterReceptionist.ReceptionistOp {
    internal init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<ReceptionistOpCodingKeys> =
            try decoder.container(keyedBy: ReceptionistOpCodingKeys.self)
        let key: AnyReceptionKey = try container.decode(AnyReceptionKey.self, forKey: .key)
        let actorID: ActorID = try container.decode(ActorID.self, forKey: .id)
        switch try container.decode(ReceptionistOpDiscriminator.self, forKey: .discriminator) {
        case .register:
            self = .register(key: key, id: actorID)

        case .remove:
            self = .remove(key: key, id: actorID)
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<ReceptionistOpCodingKeys> =
            encoder.container(keyedBy: ReceptionistOpCodingKeys.self)
        switch self {
        case let .register(key, actorID):
            try container.encode(ReceptionistOpDiscriminator.register, forKey: .discriminator)
            try container.encode(key, forKey: .key)
            try container.encode(actorID, forKey: .id)

        case let .remove(key, actorID):
            try container.encode(ReceptionistOpDiscriminator.remove, forKey: .discriminator)
            try container.encode(key, forKey: .key)
            try container.encode(actorID, forKey: .id)
        }
    }
}
