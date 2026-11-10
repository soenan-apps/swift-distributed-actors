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

extension Cluster.Member: Codable {
    private enum CodingKeys: String, CodingKey {
        case node = "node"
        case reachability = "reachability"
        case status = "status"
        case upNumber = "_upNumber"
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.node = try container.decode(Cluster.Node.self, forKey: .node)
        self.reachability = try container.decode(Cluster.MemberReachability.self, forKey: .reachability)
        self.status = try container.decode(Cluster.MemberStatus.self, forKey: .status)
        self.upNumber = try container.decodeIfPresent(Int.self, forKey: .upNumber)
    }

    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.node, forKey: .node)
        try container.encode(self.reachability, forKey: .reachability)
        try container.encode(self.status, forKey: .status)
        try container.encodeIfPresent(self.upNumber, forKey: .upNumber)
    }
}
