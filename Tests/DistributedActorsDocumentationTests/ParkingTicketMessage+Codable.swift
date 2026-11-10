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

import DistributedCluster
import Foundation
import NIO
import NIOFoundationCompat

extension ParkingTicketMessage {
    internal enum DiscriminatorKeys: String, Codable {
        case issued = "issued"
        case pay = "pay"
    }

    internal enum CodingKeys: String, CodingKey {  // or Int
        case discriminator = "_case"
        case issuedTicket = "issued_ticket"
        case payAmount = "pay_amount"
        case payTicket = "pay_ticket"
    }

    internal init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: .discriminator) {
        case .issued:
            let ticket: ParkingTicket = try container.decode(ParkingTicket.self, forKey: .issuedTicket)
            self = .issued(ticket)

        case .pay:
            let ticket: ParkingTicket = try container.decode(ParkingTicket.self, forKey: .payTicket)
            let amount: Int = try container.decode(Int.self, forKey: .payAmount)
            self = .pay(ticket, amount: amount)
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .issued(let ticket):
            try container.encode(DiscriminatorKeys.issued, forKey: .discriminator)
            try container.encode(ticket, forKey: .issuedTicket)

        case let .pay(ticket, amount):
            try container.encode(DiscriminatorKeys.pay, forKey: .discriminator)
            try container.encode(ticket, forKey: .payTicket)
            try container.encode(amount, forKey: .payAmount)
        }
    }
}
