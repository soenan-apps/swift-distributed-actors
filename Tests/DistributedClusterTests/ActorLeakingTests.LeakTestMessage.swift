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

import Atomics
import DistributedActorsConcurrencyHelpers
import DistributedActorsTestKit
import Foundation
import XCTest

@testable import DistributedCluster

extension ActorLeakingTests.LeakTestMessage: Codable {
    internal enum CodingKeys: String, CodingKey {
        case deallocated = "_deallocated"
    }

    public convenience init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        let value: Bool = try container.decode(Bool.self, forKey: CodingKeys.deallocated)
        self.init(UnsafeAtomic.create(value))
    }

    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deallocated?.load(ordering: .relaxed) ?? false, forKey: CodingKeys.deallocated)
    }
}
